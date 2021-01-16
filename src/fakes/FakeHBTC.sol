pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeHBTC is FakeERC20 {
  constructor() public FakeERC20("HBTC", "HBTC", 18, 1e26) {}
}
