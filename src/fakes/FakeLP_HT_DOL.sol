pragma solidity ^0.6.0;

import "./FakeERC20.sol";

contract FakeLP_HT_DOL is FakeERC20 {
  constructor() public FakeERC20("LP_HT_DOL", "LP_HT_DOL", 18, 1e26) {}
}
