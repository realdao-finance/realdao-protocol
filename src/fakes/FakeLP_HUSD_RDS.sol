pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeLP_HUSD_RDS is FakeERC20 {
  constructor() public FakeERC20("LP_HUSD_RDS", "LP_HUSD_RDS", 18, 1e26) {}
}
