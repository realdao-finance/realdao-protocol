pragma solidity ^0.6.0;

import "./libraries/Strings.sol";
import "./RToken.sol";
import "./DOL.sol";

/**
 * @title RealDAO' RERC20 Contract
 * @notice RTokens which wrap an EIP-20 underlying
 */
contract RERC20 is RToken {
  /**
   * @notice Initialize the new money market
   * @param _orchestrator The address of the orchestrator
   * @param _underlying The address of the underlying asset
   * @param _name ERC-20 name of this token
   * @param _symbol ERC-20 symbol of this token
   * @param _anchorSymbol The anchor asset
   * @param _parts Code fragments of  RToken
   */
  function initialize(
    address _orchestrator,
    address _underlying,
    string memory _name,
    string memory _symbol,
    string memory _anchorSymbol,
    address[] memory _parts
  ) public {
    super.initialize(_orchestrator, _name, _symbol, _anchorSymbol, _parts);

    underlying = _underlying;
    uint8 underlyingDecimals = EIP20Interface(underlying).decimals();
    initialExchangeRateMantissa = 10**(10 + uint256(underlyingDecimals));
  }

  /*** User Interface ***/

  /**
   * @notice Sender supplies assets into the market and receives rTokens in exchange
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param mintAmount The amount of the underlying asset to supply
   */
  function mint(uint256 mintAmount) external {
    mintAmount;
    relay(part1);
  }

  /**
   * @notice Sender redeems rTokens in exchange for the underlying asset
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param redeemTokens The number of rTokens to redeem into underlying
   */
  function redeem(uint256 redeemTokens) external {
    redeemTokens;
    relay(part1);
  }

  /**
   * @notice Sender borrows assets from the protocol to their own address
   * @param borrowAmount The amount of the underlying asset to borrow
   */
  function borrow(uint256 borrowAmount) external {
    borrowAmount;
    relay(part1);
  }

  /**
   * @notice Sender repays their own borrow
   * @param repayAmount The amount to repay
   */
  function repayBorrow(uint256 repayAmount) external {
    repayAmount;
    relay(part2);
  }

  /**
   * @notice Sender repays a borrow belonging to borrower
   * @param borrower the account with the debt being payed off
   * @param repayAmount The amount to repay
   */
  function repayBorrowBehalf(address borrower, uint256 repayAmount) external {
    borrower;
    repayAmount;
    relay(part2);
  }

  /**
   * @notice The sender liquidates the borrowers collateral.
   *  The collateral seized is transferred to the liquidator.
   * @param borrower The borrower of this rToken to be liquidated
   * @param repayAmount The amount of the underlying borrowed asset to repay
   * @param rTokenCollateral The market in which to seize collateral from the borrower
   */
  function liquidateBorrow(
    address borrower,
    uint256 repayAmount,
    address rTokenCollateral
  ) external {
    // bytes memory callData = abi.encodeWithSignature(
    //   "liquidateBorrow(address,uint256,address)",
    //   borrower,
    //   repayAmount,
    //   rTokenCollateral
    // );
    // relay(part2, callData);
    borrower;
    repayAmount;
    rTokenCollateral;
    relay(part2);
  }

  /**
   * @notice The sender adds to reserves.
   * @param addAmount The amount fo underlying token to add as reserves
   */
  function addReserves(uint256 addAmount) external {
    bytes memory callData = abi.encodeWithSignature("addReserves(uint256)", addAmount);
    relay(part3, callData);
  }
}
