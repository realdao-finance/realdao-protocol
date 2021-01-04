pragma solidity ^0.6.0;

import "./interfaces/DistributorInterface.sol";
import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./libraries/Strings.sol";
import "./RTokenBase.sol";

contract RTokenPart2 is RTokenBase {
  /**
   * @notice Sender repays their own borrow
   * @param repayAmount The amount to repay
   */
  function repayBorrow(uint256 repayAmount) external payable nonReentrant {
    accrueInterestInternal();
    repayBorrowFresh(msg.sender, msg.sender, repayAmount);
  }

  /**
   * @notice Sender repays a borrow belonging to borrower
   * @param borrower the account with the debt being payed off
   * @param repayAmount The amount to repay
   */
  function repayBorrowBehalf(address borrower, uint256 repayAmount) external payable nonReentrant {
    accrueInterestInternal();
    repayBorrowFresh(msg.sender, borrower, repayAmount);
  }

  /**
   * @notice The sender liquidates the borrowers collateral.
   *  The collateral seized is transferred to the liquidator.
   * @param borrower The borrower of this rToken to be liquidated
   * @param rTokenCollateral The market in which to seize collateral from the borrower
   * @param repayAmount The amount of the underlying borrowed asset to repay
   */
  function liquidateBorrow(
    address borrower,
    uint256 repayAmount,
    address rTokenCollateral
  ) external payable nonReentrant {
    accrueInterestInternal();
    RTokenInterface(rTokenCollateral).accrueInterest();
    liquidateBorrowFresh(msg.sender, borrower, repayAmount, rTokenCollateral);
  }

  //============================================================================
  // Internal methods
  //============================================================================

  struct LiquidateBorrowLocalVars {
    uint256 actualRepayAmount;
    uint256 seizeTokens;
  }

  /**
   * @notice The liquidator liquidates the borrowers collateral.
   *  The collateral seized is transferred to the liquidator.
   * @param borrower The borrower of this rToken to be liquidated
   * @param liquidator The address repaying the borrow and seizing collateral
   * @param rTokenCollateral The market in which to seize collateral from the borrower
   * @param repayAmount The amount of the underlying borrowed asset to repay
   */
  function liquidateBorrowFresh(
    address liquidator,
    address borrower,
    uint256 repayAmount,
    address rTokenCollateral
  ) internal {
    checkParams(repayAmount > 0, ERR_LIQUIDATE_REPAY_AMOUNT_ZERO, "RToken/liquidate repay amount is zero");
    checkParams(
      repayAmount != uint256(-1),
      ERR_LIQUIDATE_REPAY_AMOUNT_MAX,
      "RToken/liquidate repay amount should not be max uint"
    );
    checkBusiness(borrower != liquidator, ERR_LIQUIDATOR_IS_BORROWER, "RToken/liquidator should not be borrower");

    expect(accrualBlockNumber == getBlockNumber(), ERR_FRESHNESS_CHECK, "RToken/accrual block number check failed");

    RTokenInterface rToken = RTokenInterface(rTokenCollateral);
    expect(
      rToken.getAccrualBlockNumber() == getBlockNumber(),
      ERR_FRESHNESS_CHECK,
      "RToken/accrual block number check for collateral token failed"
    );

    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    uint256 allowed = controller.liquidateBorrowAllowed(
      address(this),
      rTokenCollateral,
      liquidator,
      borrower,
      repayAmount
    );
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want liquidate borrow but controller rejected");

    LiquidateBorrowLocalVars memory vars;
    vars.actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /* We calculate the number of collateral tokens that will be seized */
    vars.seizeTokens = controller.liquidateCalculateSeizeTokens(
      address(this),
      rTokenCollateral,
      vars.actualRepayAmount
    );

    /* Revert if borrower collateral token balance < seizeTokens */
    checkBusiness(rToken.balanceOf(borrower) >= vars.seizeTokens, ERR_LIQUIDATE_TOO_MANY, "RToken/liquidate too many");

    // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
    if (rTokenCollateral == address(this)) {
      seizeInternal(address(this), liquidator, borrower, vars.seizeTokens);
    } else {
      rToken.seize(liquidator, borrower, vars.seizeTokens);
    }
    emit LiquidateBorrow(liquidator, borrower, vars.actualRepayAmount, address(rTokenCollateral), vars.seizeTokens);
    // return vars.actualRepayAmount;
  }

  struct RepayBorrowLocalVars {
    Error err;
    MathError mathErr;
    uint256 repayAmount;
    uint256 borrowerIndex;
    uint256 accountBorrows;
    uint256 accountBorrowsNew;
    uint256 totalBorrowsNew;
    uint256 actualRepayAmount;
  }

  /**
   * @notice Borrows are repaid by another user (possibly the borrower).
   * @param payer the account paying off the borrow
   * @param borrower the account with the debt being payed off
   * @param repayAmount the amount of undelrying tokens being returned
   * @return  the actual repayment amount.
   */
  function repayBorrowFresh(
    address payer,
    address borrower,
    uint256 repayAmount
  ) internal returns (uint256) {
    expect(accrualBlockNumber == getBlockNumber(), ERR_FRESHNESS_CHECK, "RToken/accrual block number check failed");

    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    uint256 allowed = controller.repayBorrowAllowed(address(this), payer, borrower, repayAmount);
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want repay but controller rejected");

    RepayBorrowLocalVars memory vars;

    /* We remember the original borrowerIndex for verification purposes */
    vars.borrowerIndex = accountBorrows[borrower].interestIndex;

    /* We fetch the amount the borrower owes, with accumulated interest */
    vars.accountBorrows = borrowBalanceStoredInternal(borrower);

    /* If repayAmount == -1, repayAmount = accountBorrows */
    if (repayAmount == uint256(-1)) {
      vars.repayAmount = vars.accountBorrows;
    } else {
      vars.repayAmount = repayAmount;
    }

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /*
     * We call doTransferIn for the payer and the repayAmount
     *  Note: The rToken must handle variations between ERC-20 and ETH underlying.
     *  On success, the rToken holds an additional repayAmount of cash.
     *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
     *   it returns the amount actually transferred, in case of a fee.
     */
    vars.actualRepayAmount = doTransferIn(payer, vars.repayAmount);

    /*
     * We calculate the new borrower and total borrow balances, failing on underflow:
     *  accountBorrowsNew = accountBorrows - actualRepayAmount
     *  totalBorrowsNew = totalBorrows - actualRepayAmount
     */
    (vars.mathErr, vars.accountBorrowsNew) = subUInt(vars.accountBorrows, vars.actualRepayAmount);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REPAY_TOO_MANY, "RToken/repay too many");

    (vars.mathErr, vars.totalBorrowsNew) = subUInt(totalBorrows, vars.actualRepayAmount);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REPAY_UNDERFLOW, "RToken/repay substract underflow");

    /* We write the previously calculated values into storage */
    accountBorrows[borrower].principal = vars.accountBorrowsNew;
    accountBorrows[borrower].interestIndex = borrowIndex;
    totalBorrows = vars.totalBorrowsNew;

    updatePowerInternal(borrower);

    emit RepayBorrow(payer, borrower, vars.actualRepayAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);

    return vars.actualRepayAmount;
  }
}
