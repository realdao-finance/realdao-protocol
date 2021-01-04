pragma solidity ^0.6.0;

interface RTokenInterface {
  function accrueInterest() external;

  function anchorSymbol() external view returns (string memory);

  function balanceOf(address owner) external view returns (uint256);

  function balanceOfUnderlying(address owner) external view returns (uint256);

  function underlying() external view returns (address);

  function getAccrualBlockNumber() external view returns (uint256);

  function exchangeRateCurrent() external view returns (uint256);

  function borrowBalanceCurrent(address account) external view returns (uint256);

  function getAccountSnapshot(address account)
    external
    view
    returns (
      uint256,
      uint256,
      uint256
    );

  function seize(
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external;

  // only available for rDOL
  function reduceSystemSupply(uint256 amount) external;

  function increaseSystemSupply(uint256 amount) external;
}
