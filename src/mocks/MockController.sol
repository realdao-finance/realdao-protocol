pragma solidity ^0.6.0;

import "../interfaces/OrchestratorInterface.sol";
import "../interfaces/DistributorInterface.sol";

contract MockController {
  uint256 public val;
  OrchestratorInterface public orchestrator;
  mapping(address => bool) listedMarkets;

  function initialize(address _orchestrator) external {
    orchestrator = OrchestratorInterface(_orchestrator);
  }

  function isListedMarket(address token) external view returns (bool) {
    return listedMarkets[token];
  }

  function addMarket(address token) external {
    listedMarkets[token] = true;
  }

  function closePool(address token) external {
    DistributorInterface(orchestrator.getAddress("DISTRIBUTOR")).closeLendingPool(token);
  }

  function writeByCouncil(uint256 newVal) external {
    require(
      msg.sender == OrchestratorInterface(orchestrator).getAddress("COUNCIL"),
      "MockController/permission denied"
    );
    val = newVal;
  }
}
