pragma solidity ^0.6.0;

import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/EIP20Interface.sol";
import "./interfaces/EIP20NonStandardInterface.sol";
import "./interfaces/InterestRateModelInterface.sol";
import "./interfaces/OrchestratorInterface.sol";
import "./interfaces/DistributorInterface.sol";
import "./libraries/Strings.sol";
import "./libraries/Exponential.sol";
import "./AuthBase.sol";

contract RTokenBase is AuthBase, Exponential {
  /**
   * @notice Container for borrow balance information
   * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
   * @member interestIndex Global borrowIndex as of the most recent balance-changing action
   */
  struct BorrowSnapshot {
    uint256 principal;
    uint256 interestIndex;
  }

  string public name;
  string public symbol;
  uint8 public decimals;
  uint256 public totalSupply;
  string public anchorSymbol;
  address public underlying;

  uint256 public totalBorrows;
  uint256 public totalReserves;
  uint256 public initialExchangeRateMantissa;
  uint256 public reserveFactorMantissa;
  uint256 public accrualBlockNumber;

  /**
   * @notice Accumulator of the total earned interest rate since the opening of the market
   */
  uint256 public borrowIndex;

  bool notEntered;
  mapping(address => uint256) accountTokens;
  mapping(address => mapping(address => uint256)) transferAllowances;
  mapping(address => BorrowSnapshot) accountBorrows;

  uint256 constant borrowRateMaxMantissa = 0.0005e16;
  uint256 constant reserveFactorMaxMantissa = 1e18;

  uint8 constant ERR_INVALID_PARTS_LEN = 1;
  uint8 constant ERR_SNAPSHOT = 2;
  uint8 constant ERR_PRINCIPAL_CALC = 3;
  uint8 constant ERR_BORROWED_CALC = 4;
  uint8 constant ERR_REENTERED = 5;
  uint8 constant ERR_BORROW_RATE_HIGH = 6;
  uint8 constant ERR_BLOCK_DELTA_CALC = 7;
  uint8 constant ERR_ACCURE_INTEREST_CALC = 8;
  uint8 constant ERR_EXCHANGE_RATE_CALC = 9;
  uint8 constant ERR_CASH_CALC = 10;
  uint8 constant ERR_SENDER_MISMATCH = 11;
  uint8 constant ERR_VALUE_MISMATCH = 12;
  uint8 constant ERR_TRANSFER_IN_FAILED = 13;
  uint8 constant ERR_TRANSFER_IN_OVERFLOW = 14;
  uint8 constant ERR_TRANSFER_OUT_FAILED = 15;
  uint8 constant ERR_CONTROLLER_REJECTION = 16;
  uint8 constant ERR_FRESHNESS_CHECK = 17;
  uint8 constant ERR_MINT_CALC = 18;
  uint8 constant ERR_INVALID_REDEEM_PARAMS = 19;
  uint8 constant ERR_REDEEM_CALC = 20;
  uint8 constant ERR_INSUFFICIENT_CASH = 21;
  uint8 constant ERR_BORROW_CALC = 22;
  uint8 constant ERR_TRANSFER_SRC_EQUALS_DST = 23;
  uint8 constant ERR_TRANSFER_CALC = 24;
  uint8 constant ERR_ONLY_CONTROLLER = 25;
  uint8 constant ERR_SYSTEM_SUPPLY_DOL_CALC = 26;
  uint8 constant ERR_SYSTEM_REDUCE_DOL_CALC = 27;
  uint8 constant ERR_ADD_RESERVES_CALC = 28;
  uint8 constant ERR_REDUCE_RESERVES_CALC = 29;
  uint8 constant ERR_INSUFFICIENT_RESERVES = 30;
  uint8 constant ERR_INVALID_RESERVE_FACTOR = 31;
  uint8 constant ERR_SEIZE_CALC = 32;
  uint8 constant ERR_LIQUIDATOR_IS_BORROWER = 33;
  uint8 constant ERR_REPAY_CALC = 33;
  uint8 constant ERR_LIQUIDATE_TOO_MANY = 34;
  uint8 constant ERR_LIQUIDATE_REPAY_AMOUNT_MAX = 35;
  uint8 constant ERR_LIQUIDATE_REPAY_AMOUNT_ZERO = 36;
  uint8 constant ERR_BALANCE_OF_UNDERLYING_CALC = 37;
  uint8 constant ERR_TRANSFER_INSUFFICIENT_ALLOWANCE = 38;
  uint8 constant ERR_TRANSFER_INSUFFICIENT_BALANCE = 39;
  uint8 constant ERR_TRANSFER_ADDITION_OVERFLOW = 40;
  uint8 constant ERR_REDEEM_TOO_MANY = 41;
  uint8 constant ERR_REDEEM_UNDERFLOW = 42;
  uint8 constant ERR_SEIZE_TOO_MANY = 43;
  uint8 constant ERR_SEIZE_UNDERFLOW = 44;
  uint8 constant ERR_REPAY_TOO_MANY = 45;
  uint8 constant ERR_REPAY_UNDERFLOW = 46;
  uint8 constant ERR_REDUCE_DOL_TOO_MANY = 47;
  uint8 constant ERR_REDUCE_DOL_UNDERFLOW = 48;
  uint8 constant ERR_UPDATE_POWER_CALC = 49;

  event AccrueInterest(uint256 cashPrior, uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);
  event Mint(address minter, uint256 mintAmount, uint256 mintTokens);
  event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);
  event Borrow(address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);
  event RepayBorrow(address payer, address borrower, uint256 repayAmount, uint256 accountBorrows, uint256 totalBorrows);
  event LiquidateBorrow(
    address liquidator,
    address borrower,
    uint256 repayAmount,
    address RTokenCollateral,
    uint256 seizeTokens
  );

  event NewReserveFactor(uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa);
  event ReservesAdded(address benefactor, uint256 addAmount, uint256 newTotalReserves);
  event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);

  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  event Failure(uint256 error, uint256 info, uint256 detail);

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   */
  modifier nonReentrant() {
    expect(notEntered, ERR_REENTERED, "RToken/re-entered");
    notEntered = false;
    _;
    notEntered = true; // get a gas-refund post-Istanbul
  }

  modifier onlyController() {
    check(
      msg.sender == orchestrator.getMarketController(),
      ERR_TYPE_AUTH,
      ERR_ONLY_CONTROLLER,
      "RToken/only controller is allowed"
    );
    _;
  }

  /**
   * @dev Function to simply retrieve block number
   *  This exists mainly for inheriting test contracts to stub this result.
   */
  function getBlockNumber() internal view returns (uint256) {
    return block.number;
  }

  /**
   * @notice Return the borrow balance of account based on stored data
   * @param account The address whose balance should be calculated
   * @return the calculated balance or 0
   */
  function borrowBalanceStoredInternal(address account) internal view returns (uint256) {
    /* Note: we do not assert that the market is up to date */
    MathError mathErr;
    uint256 principalTimesIndex;
    uint256 result;

    /* Get borrowBalance and borrowIndex */
    BorrowSnapshot storage borrowSnapshot = accountBorrows[account];

    /* If borrowBalance = 0 then borrowIndex is likely also 0.
     * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
     */
    if (borrowSnapshot.principal == 0) {
      return 0;
    }

    /* Calculate new borrow balance using the interest index:
     *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
     */
    (mathErr, principalTimesIndex) = mulUInt(borrowSnapshot.principal, borrowIndex);
    checkMath(mathErr == MathError.NO_ERROR, ERR_PRINCIPAL_CALC, "RToken/principal calc failed");

    (mathErr, result) = divUInt(principalTimesIndex, borrowSnapshot.interestIndex);
    checkMath(mathErr == MathError.NO_ERROR, ERR_BORROWED_CALC, "RToken/borrowed balance calc failed");

    return result;
  }

  /**
   * @notice Calculates the exchange rate from the underlying to the RToken
   * @dev This function does not accrue interest before calculating the exchange rate
   * @return (error code, calculated exchange rate scaled by 1e18)
   */
  function exchangeRateStoredInternal() internal view returns (uint256) {
    if (totalSupply == 0) return initialExchangeRateMantissa;

    /*
     * Otherwise:
     *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
     */
    uint256 totalCash = getCashPrior();
    uint256 cashPlusBorrowsMinusReserves;
    Exp memory exchangeRate;
    MathError mathErr;

    (mathErr, cashPlusBorrowsMinusReserves) = addThenSubUInt(totalCash, totalBorrows, totalReserves);
    checkMath(mathErr == MathError.NO_ERROR, ERR_EXCHANGE_RATE_CALC, "RToken/exchange rate calc 1");

    (mathErr, exchangeRate) = getExp(cashPlusBorrowsMinusReserves, totalSupply);
    checkMath(mathErr == MathError.NO_ERROR, ERR_EXCHANGE_RATE_CALC, "RToken/exchange rate calc 2");

    return exchangeRate.mantissa;
  }

  /**
   * @notice Applies accrued interest to total borrows and reserves
   * @dev This calculates interest accrued from the last checkpointed block
   *   up to the current block and writes new checkpoint to storage.
   */
  function accrueInterestInternal() internal {
    /* Remember the initial block number */
    uint256 currentBlockNumber = getBlockNumber();
    uint256 accrualBlockNumberPrior = accrualBlockNumber;

    /* Short-circuit accumulating 0 interest */
    if (accrualBlockNumberPrior == currentBlockNumber) return;

    /* Read the previous values out of storage */
    uint256 cashPrior = getCashPrior();
    uint256 borrowsPrior = totalBorrows;
    uint256 reservesPrior = totalReserves;
    uint256 borrowIndexPrior = borrowIndex;

    /* Calculate the current borrow interest rate */
    InterestRateModelInterface irm = InterestRateModelInterface(orchestrator.getInterestRateModel());
    uint256 borrowRateMantissa = irm.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
    checkBusiness(
      borrowRateMantissa <= borrowRateMaxMantissa,
      ERR_BORROW_RATE_HIGH,
      "RToken/borrow rate is absurdly high"
    );

    /* Calculate the number of blocks elapsed since the last accrual */
    (MathError mathErr, uint256 blockDelta) = subUInt(currentBlockNumber, accrualBlockNumberPrior);
    checkMath(mathErr == MathError.NO_ERROR, ERR_BLOCK_DELTA_CALC, "RToken/could not calculate block delta");

    /*
     * Calculate the interest accumulated into borrows and reserves and the new index:
     *  simpleInterestFactor = borrowRate * blockDelta
     *  interestAccumulated = simpleInterestFactor * totalBorrows
     *  totalBorrowsNew = interestAccumulated + totalBorrows
     *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
     *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
     */

    Exp memory simpleInterestFactor;
    uint256 interestAccumulated;
    uint256 totalBorrowsNew;
    uint256 totalReservesNew;
    uint256 borrowIndexNew;

    (mathErr, simpleInterestFactor) = mulScalar(Exp({ mantissa: borrowRateMantissa }), blockDelta);
    checkMath(mathErr == MathError.NO_ERROR, ERR_ACCURE_INTEREST_CALC, "RToken/accure interest calc 1");

    (mathErr, interestAccumulated) = mulScalarTruncate(simpleInterestFactor, borrowsPrior);
    checkMath(mathErr == MathError.NO_ERROR, ERR_ACCURE_INTEREST_CALC, "RToken/accure interest calc 2");

    (mathErr, totalBorrowsNew) = addUInt(interestAccumulated, borrowsPrior);
    checkMath(mathErr == MathError.NO_ERROR, ERR_ACCURE_INTEREST_CALC, "RToken/accure interest calc 3");

    (mathErr, totalReservesNew) = mulScalarTruncateAddUInt(
      Exp({ mantissa: reserveFactorMantissa }),
      interestAccumulated,
      reservesPrior
    );
    checkMath(mathErr == MathError.NO_ERROR, ERR_ACCURE_INTEREST_CALC, "RToken/accure interest calc 4");

    (mathErr, borrowIndexNew) = mulScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);
    checkMath(mathErr == MathError.NO_ERROR, ERR_ACCURE_INTEREST_CALC, "RToken/accure interest calc 5");

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    accrualBlockNumber = currentBlockNumber;
    borrowIndex = borrowIndexNew;
    totalBorrows = totalBorrowsNew;
    totalReserves = totalReservesNew;

    emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);
  }

  /**
   * @notice Gets balance of this contract in terms of the underlying
   * @dev This excludes the value of the current message, if any
   * @return The quantity of underlying owned by this contract
   */
  function getCashPrior() internal view returns (uint256) {
    if (Strings.equals(symbol, "rETH")) {
      (MathError err, uint256 startingBalance) = subUInt(address(this).balance, msg.value);
      checkMath(err == MathError.NO_ERROR, ERR_CASH_CALC, "REther/cash calc failed");
      return startingBalance;
    } else {
      EIP20Interface token = EIP20Interface(underlying);
      return token.balanceOf(address(this));
    }
  }

  /**
   * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
   *  This may revert due to insufficient balance or insufficient allowance.
   */
  function doTransferIn(address from, uint256 amount) internal returns (uint256) {
    if (Strings.equals(symbol, "rETH")) {
      expect(msg.sender == from, ERR_SENDER_MISMATCH, "RToken/ether sender mismatch");
      expect(msg.value == amount, ERR_VALUE_MISMATCH, "RToken/ether value mismatch");
      return amount;
    } else {
      EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
      uint256 balanceBefore = EIP20Interface(underlying).balanceOf(address(this));
      token.transferFrom(from, address(this), amount);

      bool success;
      assembly {
        switch returndatasize()
          case 0 {
            // This is a non-standard ERC-20
            success := not(0) // set success to true
          }
          case 32 {
            // This is a compliant ERC-20
            returndatacopy(0, 0, 32)
            success := mload(0) // Set `success = returndata` of external call
          }
          default {
            // This is an excessively non-compliant ERC-20, revert.
            revert(0, 0)
          }
      }
      expect(success, ERR_TRANSFER_IN_FAILED, "RToken/erc20 transfer in failed");

      // Calculate the amount that was *actually* transferred
      uint256 balanceAfter = EIP20Interface(underlying).balanceOf(address(this));
      expect(balanceAfter >= balanceBefore, ERR_TRANSFER_IN_OVERFLOW, "RToken/transfer in overflow");
      return balanceAfter - balanceBefore;
    }
  }

  /**
   * @dev Performs a transfer out, ideally returning an explanatory error code upon failure tather than reverting.
   *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
   *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
   */
  function doTransferOut(address payable to, uint256 amount) internal {
    if (Strings.equals(symbol, "rETH")) {
      to.transfer(amount);
    } else {
      EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
      token.transfer(to, amount);

      bool success;
      assembly {
        switch returndatasize()
          case 0 {
            // This is a non-standard ERC-20
            success := not(0) // set success to true
          }
          case 32 {
            // This is a complaint ERC-20
            returndatacopy(0, 0, 32)
            success := mload(0) // Set `success = returndata` of external call
          }
          default {
            // This is an excessively non-compliant ERC-20, revert.
            revert(0, 0)
          }
      }
      expect(success, ERR_TRANSFER_OUT_FAILED, "RToken/transfer out failed");
    }
  }

  /**
   * @notice Transfers collateral tokens (this market) to the liquidator.
   * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another RToken.
   *  Its absolutely critical to use msg.sender as the seizer rToken and not a parameter.
   * @param seizerToken The contract seizing the collateral (i.e. borrowed rToken)
   * @param liquidator The account receiving seized collateral
   * @param borrower The account having collateral seized
   * @param seizeTokens The number of rTokens to seize
   */
  function seizeInternal(
    address seizerToken,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) internal {
    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    uint256 allowed = controller.seizeAllowed(address(this), seizerToken, liquidator, borrower, seizeTokens);
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want seize but controller rejected");

    checkBusiness(borrower != liquidator, ERR_LIQUIDATOR_IS_BORROWER, "RToken/liquidator should not be borrower");

    MathError mathErr;
    uint256 borrowerTokensNew;
    uint256 liquidatorTokensNew;

    /*
     * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
     *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
     *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
     */
    (mathErr, borrowerTokensNew) = subUInt(accountTokens[borrower], seizeTokens);
    checkMath(mathErr == MathError.NO_ERROR, ERR_SEIZE_CALC, "RToken/seize calculation err 1");

    (mathErr, liquidatorTokensNew) = addUInt(accountTokens[liquidator], seizeTokens);
    checkMath(mathErr == MathError.NO_ERROR, ERR_SEIZE_CALC, "RToken/seize calculation err 2");

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /* We write the previously calculated values into storage */
    accountTokens[borrower] = borrowerTokensNew;
    accountTokens[liquidator] = liquidatorTokensNew;

    updatePowerInternal(liquidator);
    updatePowerInternal(borrower);

    emit Transfer(borrower, liquidator, seizeTokens);
  }

  function updatePowerInternal(address account) internal {
    DistributorInterface distributor = DistributorInterface(orchestrator.getDistributor());
    if (distributor.isPoolActive(address(this))) {
      MathError mathErr;
      uint256 supplyPower;
      uint256 totalPower;
      (mathErr, supplyPower) = mulScalarTruncate(
        Exp({ mantissa: initialExchangeRateMantissa }),
        accountTokens[account]
      );
      checkMath(mathErr == MathError.NO_ERROR, ERR_UPDATE_POWER_CALC, "RToken/update lending power calc error 1");

      (mathErr, totalPower) = addUInt(accountBorrows[account].principal, supplyPower);
      checkMath(mathErr == MathError.NO_ERROR, ERR_UPDATE_POWER_CALC, "RToken/update lending power calc error 2");

      distributor.updateLendingPower(account, totalPower);
    }
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_RTOKEN;
  }
}
