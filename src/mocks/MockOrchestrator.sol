pragma solidity ^0.6.0;

import "../interfaces/OrchestratorInterface.sol";

contract MockOrchestrator is OrchestratorInterface {
  address public controller;
  address public oracle;
  address public interestRateModel;
  address public distributor;
  address public rds;
  address public dol;
  address public council;
  address public democracy;
  address public reporter;

  address public _guardian;

  constructor() public {
    _guardian = msg.sender;
  }

  function guardian() external override view returns (address) {
    return _guardian;
  }

  function setMarketController(address addr) external {
    controller = addr;
  }

  function setDistributor(address addr) external {
    distributor = addr;
  }

  function setOracle(address addr) external {
    oracle = addr;
  }

  function setInterestRateModel(address addr) external {
    interestRateModel = addr;
  }

  function setRDS(address addr) external {
    rds = addr;
  }

  function setCouncil(address addr) external {
    council = addr;
  }

  function setDemocracy(address addr) external {
    democracy = addr;
  }

  function getMarketController() external override view returns (address) {
    return controller;
  }

  function getOracle() external override view returns (address) {
    return oracle;
  }

  function getInterestRateModel() external override view returns (address) {
    return interestRateModel;
  }

  function getDistributor() external override view returns (address) {
    return distributor;
  }

  function getRDS() external override view returns (address) {
    return rds;
  }

  function getDOL() external override view returns (address) {
    return dol;
  }

  function getReporter() external override view returns (address) {
    return reporter;
  }

  function getCouncil() external override view returns (address) {
    return council;
  }

  function getDemocracy() external override view returns (address) {
    return democracy;
  }
}
