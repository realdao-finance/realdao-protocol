pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../MarketController.sol";

contract MockMarketControllerV2 is MarketController {
  mapping(uint256 => uint256) store;

  function write(uint256 key, uint256 val) external {
    store[key] = val;
  }

  function read(uint256 key) external view returns (uint256) {
    return store[key];
  }
}
