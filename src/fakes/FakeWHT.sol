pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeWHT is FakeERC20 {
  constructor() public FakeERC20("WHT", "WHT", 18, 1e26) {}
}
