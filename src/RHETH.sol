pragma solidity ^0.6.0;

import "./RERC20.sol";

/**
 * @title RHETH contract (EIP-20 compatible)
 * @notice HETH lending market
 */
contract RHETH is RERC20 {
  function initialize(
    address _orchestrator,
    address _underlying,
    address[] memory parts
  ) public {
    super.initialize(_orchestrator, _underlying, "RealdDAO wrapped HETH", "rHETH", "HETH", parts);
  }
}
