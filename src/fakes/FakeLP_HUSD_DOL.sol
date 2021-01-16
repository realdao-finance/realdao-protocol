pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeLP_HUSD_DOL is FakeERC20 {
  constructor() public FakeERC20("LP_HUSD_DOL", "LP_HUSD_DOL", 18, 1e26) {}
}
