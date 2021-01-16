pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeLP_HT_RDS is FakeERC20 {
  constructor() public FakeERC20("LP_HT_RDS", "LP_HT_RDS", 18, 1e26) {}
}
