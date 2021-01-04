pragma solidity ^0.6.0;

contract UpgradableProxy {
  bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
  bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

  modifier ifAdmin() {
    if (msg.sender == getAdmin()) {
      _;
    } else {
      delegateCall();
    }
  }

  function initialize(address impl, bytes calldata initialCall) external payable {
    assert(IMPLEMENTATION_SLOT == bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1));
    assert(ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
    require(getImplementation() == address(0), "UpgradableProxy/already initialized");

    setImplementation(impl);
    setAdmin(msg.sender);

    if (initialCall.length > 0) {
      (bool success, ) = impl.delegatecall(initialCall);
      require(success, "UpgradableProxy/initial call failed");
    }
  }

  fallback() external payable {
    delegateCall();
  }

  receive() external payable {
    delegateCall();
  }

  function _implementation() external view returns (address) {
    return getImplementation();
  }

  function _admin() external view returns (address) {
    return getAdmin();
  }

  function _upgrade(address newImpl) external ifAdmin {
    setImplementation(newImpl);
  }

  function delegateCall() internal {
    address impl = getImplementation();
    assembly {
      calldatacopy(0, 0, calldatasize())

      let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())

      switch result
        // delegatecall returns 0 on error.
        case 0 {
          revert(0, returndatasize())
        }
        default {
          return(0, returndatasize())
        }
    }
  }

  function getImplementation() internal view returns (address impl) {
    bytes32 slot = IMPLEMENTATION_SLOT;
    assembly {
      impl := sload(slot)
    }
  }

  function setImplementation(address newImpl) internal {
    bytes32 slot = IMPLEMENTATION_SLOT;
    assembly {
      sstore(slot, newImpl)
    }
  }

  function getAdmin() internal view returns (address adm) {
    bytes32 slot = ADMIN_SLOT;
    assembly {
      adm := sload(slot)
    }
  }

  function setAdmin(address newAdmin) internal {
    bytes32 slot = ADMIN_SLOT;
    assembly {
      sstore(slot, newAdmin)
    }
  }
}
