pragma solidity ^0.6.0;

import "./interfaces/DistributorInterface.sol";
import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./libraries/Strings.sol";
import "./RTokenBase.sol";
import "./DOL.sol";

contract RTokenPart3 is RTokenBase {
  /**
   * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
   * @dev Called by both `transfer` and `transferFrom` internally
   * @param spender The address of the account performing the transfer
   * @param src The address of the source account
   * @param dst The address of the destination account
   * @param tokens The number of tokens to transfer
   */
  function transferTokens(
    address spender,
    address src,
    address dst,
    uint256 tokens
  ) external {
    checkParams(src != dst, ERR_TRANSFER_SRC_EQUALS_DST, "RToken/transfer src should not be equal to dst");
    /* Fail if transfer not allowed */
    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getAddress("MARKET_CONTROLLER"));
    uint256 allowed = controller.transferAllowed(address(this), src, dst, tokens);
    checkBusiness(allowed == 0, ERR_CONTROLLER_REJECTION, "RToken/want transfer but controller rejected");

    /* Get the allowance, infinite for the account owner */
    uint256 startingAllowance = 0;
    if (spender == src) {
      startingAllowance = uint256(-1);
    } else {
      startingAllowance = transferAllowances[src][spender];
    }

    MathError mathErr;
    uint256 allowanceNew;
    uint256 srcTokensNew;
    uint256 dstTokensNew;

    (mathErr, allowanceNew) = subUInt(startingAllowance, tokens);
    checkMath(
      mathErr == MathError.NO_ERROR,
      ERR_TRANSFER_INSUFFICIENT_ALLOWANCE,
      "RToken/transfer insufficient allowance"
    );

    (mathErr, srcTokensNew) = subUInt(accountTokens[src], tokens);
    checkMath(mathErr == MathError.NO_ERROR, ERR_TRANSFER_INSUFFICIENT_BALANCE, "RToken/transfer insufficient balance");

    (mathErr, dstTokensNew) = addUInt(accountTokens[dst], tokens);
    checkMath(mathErr == MathError.NO_ERROR, ERR_TRANSFER_ADDITION_OVERFLOW, "RToken/transfer addition overflow");

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    accountTokens[src] = srcTokensNew;
    accountTokens[dst] = dstTokensNew;

    /* Eat some of the allowance (if necessary) */
    if (startingAllowance != uint256(-1)) {
      transferAllowances[src][spender] = allowanceNew;
    }

    updatePowerInternal(dst);
    updatePowerInternal(src);

    emit Transfer(src, dst, tokens);
  }

  struct IncreaseSupplyLocalVars {
    Error err;
    MathError mathErr;
    uint256 mintTokens;
    uint256 totalSupplyNew;
    uint256 accountTokensNew;
  }

  function increaseSystemSupply(address rDOL, uint256 amount) external {
    accrueInterestInternal();

    IncreaseSupplyLocalVars memory vars;

    DOL(underlying).mint(rDOL, amount);

    // system should not earn interest, there is no need to calculate with exchange rate
    // assert: the rDOL and DOL have the same decimals, so the mintTokens equals amount
    vars.mintTokens = amount;

    /*
     * We calculate the new total supply of rTokens and minter token balance, checking for overflow:
     *  totalSupplyNew = totalSupply + mintTokens
     *  accountTokensNew = accountTokens[minter] + mintTokens
     */
    (vars.mathErr, vars.totalSupplyNew) = addUInt(totalSupply, vars.mintTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_SYSTEM_SUPPLY_DOL_CALC, "RToken/system supply DOL calc 1");

    (vars.mathErr, vars.accountTokensNew) = addUInt(accountTokens[rDOL], vars.mintTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_SYSTEM_SUPPLY_DOL_CALC, "RToken/system supply DOL calc 2");

    // emit Mint(rDOL, vars.actualMintAmount, vars.mintTokens);
    // emit Transfer(address(0), rDOL, vars.mintTokens);

    totalSupply = vars.totalSupplyNew;
    accountTokens[rDOL] = vars.accountTokensNew;
  }

  struct ReduceSupplyLocalVars {
    Error err;
    MathError mathErr;
    uint256 redeemTokens;
    uint256 redeemAmount;
    uint256 totalSupplyNew;
    uint256 accountTokensNew;
  }

  function reduceSystemSupply(address rDOL, uint256 amount) external {
    accrueInterestInternal();

    ReduceSupplyLocalVars memory vars;

    // system should not earn interest, there is no need to calculate with exchange rate
    // assert: the rDOL and DOL have the same decimals, so the redeemTokens equals redeemAmount
    vars.redeemTokens = amount;
    vars.redeemAmount = amount;

    /*
     * We calculate the new total supply and redeemer balance, checking for underflow:
     *  totalSupplyNew = totalSupply - redeemTokens
     *  accountTokensNew = accountTokens[redeemer] - redeemTokens
     */
    (vars.mathErr, vars.totalSupplyNew) = subUInt(totalSupply, vars.redeemTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REDUCE_DOL_UNDERFLOW, "RToken/system reduce underflow");

    (vars.mathErr, vars.accountTokensNew) = subUInt(accountTokens[rDOL], vars.redeemTokens);
    checkMath(vars.mathErr == MathError.NO_ERROR, ERR_REDUCE_DOL_TOO_MANY, "RToken/system reduce too many");

    /* Fail gracefully if protocol has insufficient cash */
    checkBusiness(
      getCashPrior() >= vars.redeemAmount,
      ERR_INSUFFICIENT_CASH,
      "RToken/want reduce system DOL but insufficient cash"
    );

    DOL(underlying).burn(rDOL, vars.redeemAmount);

    /* We write previously calculated values into storage */
    totalSupply = vars.totalSupplyNew;
    accountTokens[rDOL] = vars.accountTokensNew;

    // emit Transfer(rDOL, rDOL, vars.redeemTokens);
  }

  /**
   * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
   * @dev Admin function to accrue interest and set a new reserve factor
   */
  function setReserveFactor(uint256 newReserveFactorMantissa) external onlyCouncil nonReentrant {
    checkParams(
      newReserveFactorMantissa <= reserveFactorMaxMantissa,
      ERR_INVALID_RESERVE_FACTOR,
      "RToken/set for reserve factor too large"
    );
    accrueInterestInternal();
    emit NewReserveFactor(reserveFactorMantissa, newReserveFactorMantissa);
    reserveFactorMantissa = newReserveFactorMantissa;
  }

  /**
   * @notice Accrues interest and reduces reserves by transferring from msg.sender
   * @param addAmount Amount of addition to reserves
   */
  function addReserves(uint256 addAmount) external nonReentrant {
    accrueInterestInternal();

    /*
     * We call doTransferIn for the caller and the addAmount
     *  Note: The rToken must handle variations between ERC-20 and ETH underlying.
     *  On success, the rToken holds an additional addAmount of cash.
     *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
     *  it returns the amount actually transferred, in case of a fee.
     */

    uint256 actualAddAmount = doTransferIn(msg.sender, addAmount);
    uint256 totalReservesNew = totalReserves + actualAddAmount;
    checkMath(totalReservesNew >= totalReserves, ERR_ADD_RESERVES_CALC, "RToken/reserves addition overflow");

    totalReserves = totalReservesNew;

    emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);
  }

  /**
   * @notice Accrues interest and reduces reserves by transferring to admin
   * @param reduceAmount Amount of reduction to reserves
   */
  function reduceReserves(uint256 reduceAmount, address payable recipient) external onlyCouncil nonReentrant {
    accrueInterestInternal();
    checkBusiness(
      getCashPrior() >= reduceAmount,
      ERR_INSUFFICIENT_CASH,
      "RToken/want reduce reserves but insufficient cash"
    );

    checkBusiness(totalReserves >= reduceAmount, ERR_INSUFFICIENT_RESERVES, "RToken/reduce too many reserves");

    uint256 totalReservesNew = totalReserves - reduceAmount;
    checkMath(
      totalReservesNew <= totalReserves,
      ERR_REDUCE_RESERVES_CALC,
      "RToken/reserves reduce subtraction underflow"
    );

    totalReserves = totalReservesNew;
    doTransferOut(recipient, reduceAmount);
    emit ReservesReduced(recipient, reduceAmount, totalReservesNew);
  }
}
