pragma solidity ^0.6.0;

interface OrchestratorInterface {
  function guardian() external view returns (address);

  function getAddress(string calldata key) external view returns (address);
}
