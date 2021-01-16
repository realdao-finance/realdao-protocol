pragma solidity ^0.6.0;

import "./RERC20.sol";

/**
 * @title RHBTC contract (EIP-20 compatible)
 * @notice HBTC lending market
 */
contract RHBTC is RERC20 {
  function initialize(
    address _orchestrator,
    address _underlying,
    address[] memory parts
  ) public {
    super.initialize(_orchestrator, _underlying, "RealdDAO wrapped HBTC", "rHBTC", "HBTC", parts);
  }
}
