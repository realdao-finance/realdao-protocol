pragma solidity ^0.6.0;

contract MockOrchestrator {
  address public controller;
  address public oracle;
  address public interestRateModel;
  address public distributor;
  address public rds;
  address public dol;
  address public council;
  address public democracy;
  address public reporter;
  mapping(string => address) contracts;

  address public _guardian;

  constructor() public {
    _guardian = msg.sender;
  }

  function guardian() external view returns (address) {
    return _guardian;
  }

  function setMarketController(address addr) external {
    contracts["MARKET_CONTROLLER"] = addr;
  }

  function setDistributor(address addr) external {
    contracts["DISTRIBUTOR"] = addr;
  }

  function setOracle(address addr) external {
    contracts["ORACLE"] = addr;
  }

  function setInterestRateModel(address addr) external {
    contracts["INTEREST_RATE_MODEL"] = addr;
  }

  function setRDS(address addr) external {
    contracts["RDS"] = addr;
  }

  function setCouncil(address addr) external {
    contracts["COUNCIL"] = addr;
  }

  function setDemocracy(address addr) external {
    contracts["DEMOCRACY"] = addr;
  }

  function getAddress(string calldata key) external view returns (address) {
    return contracts[key];
  }
}
