pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeHETH is FakeERC20 {
  constructor() public FakeERC20("HETH", "HETH", 18, 1e26) {}
}
