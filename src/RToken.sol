pragma solidity ^0.6.0;

import "./interfaces/EIP20Interface.sol";
import "./interfaces/EIP20NonStandardInterface.sol";
import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./interfaces/InterestRateModelInterface.sol";
import "./interfaces/OrchestratorInterface.sol";
import "./interfaces/DistributorInterface.sol";
import "./libraries/Strings.sol";
import "./RTokenBase.sol";

contract RToken is RTokenBase {
  address public part1;
  address public part2;
  address public part3;

  /**
   * @notice Initialize the money market
   * @param _orchestrator The address of the MarketController
   * @param _name EIP-20 name of this token
   * @param _symbol EIP-20 symbol of this token
   * @param _anchor Anchor symbol of this token
   * @param _parts Code fragments of  RToken
   */
  function initialize(
    address _orchestrator,
    string memory _name,
    string memory _symbol,
    string memory _anchor,
    address[] memory _parts
  ) public {
    checkParams(_parts.length == 3, ERR_INVALID_PARTS_LEN, "RToken/must provide 3 parts of impls");
    super.initialize(_orchestrator);

    name = _name;
    symbol = _symbol;
    decimals = 8;
    anchorSymbol = _anchor;

    part1 = _parts[0];
    part2 = _parts[1];
    part3 = _parts[2];

    // Initialize block number and borrow index (block number mocks depend on controller being set)
    accrualBlockNumber = getBlockNumber();
    borrowIndex = mantissaOne;
    reserveFactorMantissa = 1e17; // 10%

    // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
    notEntered = true;
  }

  /**
   * @notice Transfer `amount` tokens from `msg.sender` to `dst`
   * @param dst The address of the destination account
   * @param amount The number of tokens to transfer
   * @return Whether or not the transfer succeeded
   */
  function transfer(address dst, uint256 amount) external nonReentrant returns (bool) {
    bytes memory callData = abi.encodeWithSignature(
      "transferTokens(address,address,address,uint256)",
      msg.sender,
      msg.sender,
      dst,
      amount
    );
    relay(part3, callData);
    return true;
  }

  /**
   * @notice Transfer `amount` tokens from `src` to `dst`
   * @param src The address of the source account
   * @param dst The address of the destination account
   * @param amount The number of tokens to transfer
   * @return Whether or not the transfer succeeded
   */
  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) external nonReentrant returns (bool) {
    bytes memory callData = abi.encodeWithSignature(
      "transferTokens(address,address,address,uint256)",
      msg.sender,
      src,
      dst,
      amount
    );
    relay(part3, callData);
    return true;
  }

  /**
   * @notice Approve `spender` to transfer up to `amount` from `src`
   * @dev This will overwrite the approval amount for `spender`
   *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
   * @param spender The address of the account which may transfer tokens
   * @param amount The number of tokens that are approved (-1 means infinite)
   * @return Whether or not the approval succeeded
   */
  function approve(address spender, uint256 amount) external returns (bool) {
    address src = msg.sender;
    transferAllowances[src][spender] = amount;
    emit Approval(src, spender, amount);
    return true;
  }

  /**
   * @notice Get the current allowance from `owner` for `spender`
   * @param owner The address of the account which owns the tokens to be spent
   * @param spender The address of the account which may transfer tokens
   * @return The number of tokens allowed to be spent (-1 means infinite)
   */
  function allowance(address owner, address spender) external view returns (uint256) {
    return transferAllowances[owner][spender];
  }

  /**
   * @notice Transfers collateral tokens (this market) to the liquidator.
   * @dev Will fail unless called by another rToken during the process of liquidation.
   *  Its absolutely critical to use msg.sender as the borrowed rToken and not a parameter.
   * @param liquidator The account receiving seized collateral
   * @param borrower The account having collateral seized
   * @param seizeTokens The number of rTokens to seize
   */
  function seize(
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external nonReentrant {
    seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
  }

  function accrueInterest() external {
    accrueInterestInternal();
  }

  function getAccrualBlockNumber() external view returns (uint256) {
    return accrualBlockNumber;
  }

  /**
   * @notice Get a snapshot of the account's balances, and the cached exchange rate
   * @dev This is used by controller to more efficiently perform liquidity checks.
   * @param account Address of the account to snapshot
   * @return (token balance, borrow balance, exchange rate mantissa)
   */
  function getAccountSnapshot(address account)
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 rTokenBalance = accountTokens[account];
    uint256 borrowBalance = borrowBalanceStoredInternal(account);
    uint256 exchangeRateMantissa = exchangeRateStoredInternal();
    return (rTokenBalance, borrowBalance, exchangeRateMantissa);
  }

  /**
   * @notice Get the token balance of the `owner`
   * @param owner The address of the account to query
   * @return The number of tokens owned by `owner`
   */
  function balanceOf(address owner) external view returns (uint256) {
    return accountTokens[owner];
  }

  /**
   * @notice Get the underlying balance of the `owner`
   * @param owner The address of the account to query
   * @return The amount of underlying owned by `owner`
   */
  function balanceOfUnderlying(address owner) external view returns (uint256) {
    Exp memory exchangeRate = Exp({ mantissa: exchangeRateStoredInternal() });
    (MathError mErr, uint256 balance) = mulScalarTruncate(exchangeRate, accountTokens[owner]);
    checkMath(mErr == MathError.NO_ERROR, ERR_BALANCE_OF_UNDERLYING_CALC, "RToken/balance calc for underlying failed");
    return balance;
  }

  /**
   * @notice Get cash balance of this rToken in the underlying asset
   * @return The quantity of underlying asset owned by this contract
   */
  function getCash() external view returns (uint256) {
    return getCashPrior();
  }

  /**
   * @notice Returns the current per-block supply interest rate for this rToken
   * @return The supply interest rate per block, scaled by 1e18
   */
  function supplyRatePerBlock() external view returns (uint256) {
    InterestRateModelInterface irm = InterestRateModelInterface(orchestrator.getAddress("INTEREST_RATE_MODEL"));
    if (Strings.equals(symbol, "rDOL")) {
      return irm.getSupplyRate2(getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa);
    } else {
      return irm.getSupplyRate(getCashPrior(), totalBorrows, totalReserves, reserveFactorMantissa);
    }
  }

  /**
   * @notice Returns the current per-block borrow interest rate for this rToken
   * @return The borrow interest rate per block, scaled by 1e18
   */
  function borrowRatePerBlock() external view returns (uint256) {
    InterestRateModelInterface irm = InterestRateModelInterface(orchestrator.getAddress("INTEREST_RATE_MODEL"));
    return irm.getBorrowRate(getCashPrior(), totalBorrows, totalReserves);
  }

  function exchangeRateCurrent() external view returns (uint256) {
    // require(accrueInterestInternal() == uint(Error.NO_ERROR), "accrue interest failed");
    return exchangeRateStoredInternal();
  }

  function borrowBalanceCurrent(address account) external view returns (uint256) {
    // require(accrueInterestInternal() == uint(Error.NO_ERROR), "accrue interest failed");
    return borrowBalanceStoredInternal(account);
  }

  function setReserveFactor(uint256 newReserveFactorMantissa) external onlyCouncil nonReentrant {
    newReserveFactorMantissa;
    relay(part3);
  }

  function reduceReserves(uint256 reduceAmount, address payable recipient) external onlyCouncil nonReentrant {
    reduceAmount;
    recipient;
    relay(part3);
  }

  function relay(address target) internal {
    assembly {
      let ptr := mload(0x40)
      calldatacopy(ptr, 0, calldatasize())
      let result := delegatecall(gas(), target, ptr, calldatasize(), 0, 0)
      let size := returndatasize()
      returndatacopy(ptr, 0, size)

      switch result
        case 0 {
          revert(ptr, size)
        }
        default {
          return(ptr, size)
        }
    }
  }

  function relay(address target, bytes memory callData) internal {
    (bool success, ) = target.delegatecall(callData);
    if (!success) {
      assembly {
        let ptr := mload(0x40)
        let size := returndatasize()
        returndatacopy(ptr, 0, size)
        revert(ptr, size)
      }
    }
  }
}
