pragma solidity ^0.6.0;

interface OrchestratorInterface {
  function guardian() external view returns (address);

  function getRDS() external view returns (address);

  function getDOL() external view returns (address);

  function getOracle() external view returns (address);

  function getInterestRateModel() external view returns (address);

  function getMarketController() external view returns (address);

  function getDistributor() external view returns (address);

  function getReporter() external view returns (address);

  function getDemocracy() external view returns (address);

  function getCouncil() external view returns (address);
}
