pragma solidity ^0.6.0;

import "./RERC20.sol";

/**
 * @title RWHT contract (EIP-20 compatible)
 * @notice WHT lending market
 */
contract RWHT is RERC20 {
  function initialize(
    address _orchestrator,
    address _underlying,
    address[] memory parts
  ) public {
    super.initialize(_orchestrator, _underlying, "RealdDAO wrapped WHT", "rWHT", "WHT", parts);
  }
}
