pragma solidity ^0.6.0;

import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/DistributorInterface.sol";
import "./RTokenBase.sol";

contract RTokenPart1 is RTokenBase {
  /**
   * @notice Sender supplies assets into the market and receives rTokens in exchange
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param mintAmount The amount of the underlying asset to supply
   */
  function mint(uint256 mintAmount) external payable nonReentrant {
    accrueInterestInternal();
    mintFresh(msg.sender, mintAmount);
  }

  struct MintLocalVars {
    Error err;
    MathError mathErr;
    uint256 exchangeRateMantissa;
    uint256 mintTokens;
    uint256 totalSupplyNew;
    uint256 accountTokensNew;
    uint256 actualMintAmount;
  }

  /**
   * @notice User supplies assets into the market and receives rTokens in exchange
   * @dev Assumes interest has already been accrued up to the current block
   * @param minter The address of the account which is supplying the assets
   * @param mintAmount The amount of the underlying asset to supply
   */
  function mintFresh(address minter, uint256 mintAmount) internal {
    expect(accrualBlockNumber == getBlockNumber(), ERR_FRESHNESS_CHECK, "RToken/accrual block number check failed");

    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    uint256 allowed = controller.mintAllowed(address(this), minter, mintAmount);
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want mint but controller rejected");

    MintLocalVars memory vars;
    vars.exchangeRateMantissa = exchangeRateStoredInternal();

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /*
     *  We call `doTransferIn` for the minter and the mintAmount.
     *  Note: The rToken must handle variations between ERC-20 and ETH underlying.
     *  `doTransferIn` reverts if anything goes wrong, since we can't be sure if
     *  side-effects occurred. The function returns the amount actually transferred,
     *  in case of a fee. On success, the rToken holds an additional `actualMintAmount`
     *  of cash.
     */
    vars.actualMintAmount = doTransferIn(minter, mintAmount);

    /*
     * We get the current exchange rate and calculate the number of rTokens to be minted:
     *  mintTokens = actualMintAmount / exchangeRate
     */

    (vars.mathErr, vars.mintTokens) = divScalarByExpTruncate(
      vars.actualMintAmount,
      Exp({ mantissa: vars.exchangeRateMantissa })
    );
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_MINT_CALC, "RToken/mint calc 1");

    /*
     * We calculate the new total supply of rTokens and minter token balance, checking for overflow:
     *  totalSupplyNew = totalSupply + mintTokens
     *  accountTokensNew = accountTokens[minter] + mintTokens
     */
    (vars.mathErr, vars.totalSupplyNew) = addUInt(totalSupply, vars.mintTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_MINT_CALC, "RToken/mint calc 2");

    (vars.mathErr, vars.accountTokensNew) = addUInt(accountTokens[minter], vars.mintTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_MINT_CALC, "RToken/mint calc 3");

    /* We write previously calculated values into storage */
    totalSupply = vars.totalSupplyNew;
    accountTokens[minter] = vars.accountTokensNew;

    updatePowerInternal(minter);

    emit Mint(minter, vars.actualMintAmount, vars.mintTokens);
    emit Transfer(address(this), minter, vars.mintTokens);
  }

  /**
   * @notice Sender redeems rTokens in exchange for the underlying asset
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param redeemTokens The number of rTokens to redeem into underlying
   */
  function redeem(uint256 redeemTokens) external nonReentrant {
    accrueInterestInternal();
    redeemFresh(msg.sender, redeemTokens, 0);
  }

  struct RedeemLocalVars {
    Error err;
    MathError mathErr;
    uint256 exchangeRateMantissa;
    uint256 redeemTokens;
    uint256 redeemAmount;
    uint256 totalSupplyNew;
    uint256 accountTokensNew;
  }

  /**
   * @notice User redeems rTokens in exchange for the underlying asset
   * @dev Assumes interest has already been accrued up to the current block
   * @param redeemer The address of the account which is redeeming the tokens
   * @param redeemTokensIn The number of rTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
   * @param redeemAmountIn The number of underlying tokens to receive from redeeming rTokens (only one of redeemTokensIn or redeemAmountIn may be non-zero)
   */
  function redeemFresh(
    address payable redeemer,
    uint256 redeemTokensIn,
    uint256 redeemAmountIn
  ) internal {
    checkParams(
      redeemTokensIn == 0 || redeemAmountIn == 0,
      ERR_INVALID_REDEEM_PARAMS,
      "RToken/one of redeemTokensIn or redeemAmountIn must be zero"
    );

    RedeemLocalVars memory vars;
    vars.exchangeRateMantissa = exchangeRateStoredInternal();
    if (redeemTokensIn > 0) {
      /*
       * We calculate the exchange rate and the amount of underlying to be redeemed:
       *  redeemTokens = redeemTokensIn
       *  redeemAmount = redeemTokensIn x exchangeRateCurrent
       */
      vars.redeemTokens = redeemTokensIn;
      (vars.mathErr, vars.redeemAmount) = mulScalarTruncate(
        Exp({ mantissa: vars.exchangeRateMantissa }),
        redeemTokensIn
      );
      checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REDEEM_CALC, "RToken/redeem calc 1");
    } else {
      /*
       * We get the current exchange rate and calculate the amount to be redeemed:
       *  redeemTokens = redeemAmountIn / exchangeRate
       *  redeemAmount = redeemAmountIn
       */

      (vars.mathErr, vars.redeemTokens) = divScalarByExpTruncate(
        redeemAmountIn,
        Exp({ mantissa: vars.exchangeRateMantissa })
      );
      checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REDEEM_CALC, "RToken/redeem calc 2");

      vars.redeemAmount = redeemAmountIn;
    }
    expect(accrualBlockNumber == getBlockNumber(), ERR_FRESHNESS_CHECK, "RToken/accrual block number check failed");

    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    uint256 allowed = controller.redeemAllowed(address(this), redeemer, vars.redeemTokens);
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want redeem but controller rejected");

    /*
     * We calculate the new total supply and redeemer balance, checking for underflow:
     *  totalSupplyNew = totalSupply - redeemTokens
     *  accountTokensNew = accountTokens[redeemer] - redeemTokens
     */
    (vars.mathErr, vars.totalSupplyNew) = subUInt(totalSupply, vars.redeemTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REDEEM_UNDERFLOW, "RToken/redeem substract underflow");

    (vars.mathErr, vars.accountTokensNew) = subUInt(accountTokens[redeemer], vars.redeemTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REDEEM_TOO_MANY, "RToken/redeem too many");

    /* Fail gracefully if protocol has insufficient cash */
    checkBusiness(
      getCashPrior() >= vars.redeemAmount,
      ERR_INSUFFICIENT_CASH,
      "RToken/want redeem but insufficient cash"
    );

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /*
     * We invoke doTransferOut for the redeemer and the redeemAmount.
     *  Note: The rToken must handle variations between ERC-20 and ETH underlying.
     *  On success, the rToken has redeemAmount less of cash.
     *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
     */
    doTransferOut(redeemer, vars.redeemAmount);

    /* We write previously calculated values into storage */
    totalSupply = vars.totalSupplyNew;
    accountTokens[redeemer] = vars.accountTokensNew;

    updatePowerInternal(redeemer);

    emit Transfer(redeemer, address(this), vars.redeemTokens);
    emit Redeem(redeemer, vars.redeemAmount, vars.redeemTokens);
  }

  /**
   * @notice Sender borrows assets from the protocol to their own address
   * @param borrowAmount The amount of the underlying asset to borrow
   */
  function borrow(uint256 borrowAmount) external nonReentrant {
    accrueInterestInternal();
    borrowFresh(msg.sender, borrowAmount);
  }

  struct BorrowLocalVars {
    MathError mathErr;
    uint256 accountBorrows;
    uint256 accountBorrowsNew;
    uint256 totalBorrowsNew;
  }

  /**
   * @notice Users borrow assets from the protocol to their own address
   * @param borrowAmount The amount of the underlying asset to borrow
   */
  function borrowFresh(address payable borrower, uint256 borrowAmount) internal {
    expect(accrualBlockNumber == getBlockNumber(), ERR_FRESHNESS_CHECK, "RToken/accrual block number check failed");

    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    uint256 allowed = controller.borrowAllowed(address(this), borrower, borrowAmount);
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want borrow but controller rejected");

    /* Fail gracefully if protocol has insufficient underlying cash */
    checkBusiness(getCashPrior() >= borrowAmount, ERR_INSUFFICIENT_CASH, "RToken/want borrow but insufficient cash");

    BorrowLocalVars memory vars;

    /*
     * We calculate the new borrower and total borrow balances, failing on overflow:
     *  accountBorrowsNew = accountBorrows + borrowAmount
     *  totalBorrowsNew = totalBorrows + borrowAmount
     */
    vars.accountBorrows = borrowBalanceStoredInternal(borrower);

    (vars.mathErr, vars.accountBorrowsNew) = addUInt(vars.accountBorrows, borrowAmount);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_BORROW_CALC, "RToken/borrow calc 1");

    (vars.mathErr, vars.totalBorrowsNew) = addUInt(totalBorrows, borrowAmount);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_BORROW_CALC, "RToken/borrow calc 2");

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /*
     * We invoke doTransferOut for the borrower and the borrowAmount.
     *  Note: The rToken must handle variations between ERC-20 and ETH underlying.
     *  On success, the rToken borrowAmount less of cash.
     *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
     */
    doTransferOut(borrower, borrowAmount);

    /* We write the previously calculated values into storage */
    accountBorrows[borrower].principal = vars.accountBorrowsNew;
    accountBorrows[borrower].interestIndex = borrowIndex;
    totalBorrows = vars.totalBorrowsNew;

    updatePowerInternal(borrower);

    emit Borrow(borrower, borrowAmount, vars.accountBorrowsNew, vars.totalBorrowsNew);
  }
}
