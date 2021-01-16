pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

interface PriceOracleInterface {
  function getUnderlyingPrice(address rToken) external view returns (uint256);

  function setUnderlyingPrices(string[] calldata symbols, uint256[] calldata prices) external;
}
