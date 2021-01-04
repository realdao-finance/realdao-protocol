pragma solidity ^0.6.0;

import "./RToken.sol";

contract REther is RToken {
  function initialize(address _orchestrator, address[] memory _parts) public {
    super.initialize(_orchestrator, "RealDAO wrapped ETH", "rETH", "ETH", _parts);
    initialExchangeRateMantissa = 1e28;
  }

  /**
   * @notice Send Ether to REther to mint
   */
  /* solium-disable-next-line */
  receive() external payable {
    bytes memory callData = abi.encodeWithSignature("mint(uint256)", msg.value);
    relay(part1, callData);
  }

  /**
   * @notice Sender supplies assets into the market and receives rTokens in exchange
   * @dev Reverts upon any failure
   */
  function mint() external payable {
    bytes memory callData = abi.encodeWithSignature("mint(uint256)", msg.value);
    relay(part1, callData);
  }

  /**
   * @notice The sender liquidates the borrowers collateral.
   *  The collateral seized is transferred to the liquidator.
   * @dev Reverts upon any failure
   * @param borrower The borrower of this rToken to be liquidated
   * @param rTokenCollateral The market in which to seize collateral from the borrower
   */
  function liquidateBorrow(address borrower, address rTokenCollateral) external payable {
    bytes memory callData = abi.encodeWithSignature(
      "liquidateBorrow(address,uint256,address)",
      borrower,
      msg.value,
      rTokenCollateral
    );
    relay(part2, callData);
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
   * @dev Reverts upon any failure
   */
  function repayBorrow() external payable {
    bytes memory callData = abi.encodeWithSignature("repayBorrow(uint256)", msg.value);
    relay(part2, callData);
  }

  /**
   * @notice Sender repays a borrow belonging to borrower
   * @dev Reverts upon any failure
   * @param borrower the account with the debt being payed off
   */
  function repayBorrowBehalf(address borrower) external payable {
    bytes memory callData = abi.encodeWithSignature("repayBorrowBehalf(address, uint256)", borrower, msg.value);
    relay(part2, callData);
  }
}
