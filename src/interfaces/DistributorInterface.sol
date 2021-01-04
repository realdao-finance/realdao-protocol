pragma solidity ^0.6.0;

interface DistributorInterface {
  function isPoolActive(address token) external view returns (bool);

  function createLendingPool(address rToken, uint256 startBlock) external;

  function updateLendingPower(address account, uint256 amount) external;

  function closeLendingPool(address rToken) external;
}
