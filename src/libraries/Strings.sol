pragma solidity ^0.6.0;

library Strings {
  function equals(string memory _a, string memory _b) internal pure returns (bool) {
    // return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    bytes memory a = bytes(_a);
    bytes memory b = bytes(_b);
    if (a.length != b.length) {
      return false;
    }
    for (uint16 i; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  function toString(uint256 _n) internal pure returns (string memory) {
    bytes memory buf = new bytes(32);
    uint256 len = 0;
    uint256 n = _n;
    while (n != 0) {
      buf[len++] = bytes1(uint8(n % 10) + 48);
      n /= 10;
    }
    bytes memory data = new bytes(len);
    for (uint256 i = 0; i < len; i++) {
      data[i] = buf[len - i - 1];
    }
    return string(data);
  }

  function toString(int256 n) internal pure returns (string memory) {
    if (n >= 0) {
      return toString(uint256(n));
    } else {
      return string(abi.encodePacked("-", toString(uint256(n))));
    }
  }
}
