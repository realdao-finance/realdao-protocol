pragma solidity ^0.6.0;

interface PriceOracleInterface {
  event NewPriceFeedAddress(address operator, string symbol, address addr);

  function getUnderlyingPrice(address rToken) external view returns (uint256);

  function setPriceFeedAddress(string calldata symbol, address addr) external;

  function setUnderlyingPrice(string calldata symbol, uint256 price) external;
}
