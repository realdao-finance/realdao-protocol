pragma solidity ^0.6.0;

import "./interfaces/OrchestratorInterface.sol";
import "./UpgradableProxy.sol";

/**
 * @title Supreme contract
 */
contract Supreme {
  address public orchestrator;

  event OrchestratorCreated(address impl);
  event OrchestratorUpgraded(address oldImpl, address newImpl);

  /**
   * @notice Initialize the Supreme contract
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) external {
    require(address(orchestrator) == address(0), "Supreme/already initialized");

    UpgradableProxy proxy = new UpgradableProxy();
    proxy.initialize(_orchestrator, new bytes(0));
    orchestrator = address(proxy);
    emit OrchestratorCreated(_orchestrator);
  }

  /**
   * @notice Upgrade Orchestrator contract implementation
   * @param newImpl The address of the new Orchestrator contract
   */
  function upgradeOrchestrator(address newImpl) external {
    require(address(orchestrator) != address(0), "Supreme/not initialized");

    OrchestratorInterface oi = OrchestratorInterface(orchestrator);
    address sender = msg.sender;
    require(sender == oi.guardian() || sender == oi.getAddress("DEMOCRACY"), "Supreme/permission denied");

    address payable proxyAddr = address(uint160(orchestrator));
    UpgradableProxy proxy = UpgradableProxy(proxyAddr);
    address oldImpl = proxy._implementation();
    proxy._upgrade(newImpl);
    emit OrchestratorUpgraded(oldImpl, newImpl);
  }
}
