pragma solidity ^0.6.0;

import "./RERC20.sol";
import "./DOL.sol";

/**
 * @title RDOL contract (EIP-20 compatible)
 * @notice DOL lending and forging market
 */
contract RDOL is RERC20 {
  event SystemSupplied(uint256 amount);
  event SystemReduced(uint256 amount);

  function initialize(
    address _orchestrator,
    address _underlying,
    address[] memory parts
  ) public {
    super.initialize(_orchestrator, _underlying, "RealdDAO wrapped DOL", "rDOL", "USD", parts);

    uint256 dolFirstSupply = 1e16; // 100 million
    increaseSystemSupplyInternal(dolFirstSupply);
  }

  function increaseSystemSupply(uint256 amount) external onlyCouncil {
    increaseSystemSupplyInternal(amount);
  }

  function reduceSystemSupply(uint256 amount) external onlyCouncil {
    bytes memory callData = abi.encodeWithSignature("reduceSystemSupply(address,uint256)", address(this), amount);
    relay(part3, callData);
    emit SystemReduced(amount);
  }

  function increaseSystemSupplyInternal(uint256 amount) internal {
    bytes memory callData = abi.encodeWithSignature("increaseSystemSupply(address,uint256)", address(this), amount);
    relay(part3, callData);
    emit SystemSupplied(amount);
  }
}
