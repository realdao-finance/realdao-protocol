pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../interfaces/EIP20Interface.sol";
import "../interfaces/RTokenInterface.sol";
import "../libraries/Strings.sol";
import "../libraries/SafeMath.sol";

contract MockPriceOracle {
  using SafeMath for uint256;

  address public admin;
  mapping(string => uint256) assetPrices;

  function initialize(address _admin) external {
    admin = _admin;
    assetPrices["ETH"] = 400e8;
    assetPrices["USD"] = 1e8;
  }

  function getUnderlyingPrice(address rTokenAddr) external view returns (uint256) {
    RTokenInterface rToken = RTokenInterface(rTokenAddr);
    string memory symbol = rToken.anchorSymbol();
    uint256 underlyingDecimals;
    if (Strings.equals(symbol, "ETH")) {
      underlyingDecimals = 18;
    } else {
      underlyingDecimals = EIP20Interface(rToken.underlying()).decimals();
    }
    require(underlyingDecimals <= 18, "PriceOracle/underlying decimals overflow");
    uint256 price = getPrice(symbol);
    return price.mul(10**(18 - underlyingDecimals));
  }

  function setUnderlyingPrices(string[] calldata symbols, uint256[] calldata prices) external {
    for (uint256 i = 0; i < symbols.length; i++) {
      assetPrices[symbols[i]] = prices[i];
    }
  }

  function getPrice(string memory symbol) internal view returns (uint256) {
    return assetPrices[symbol];
  }
}
