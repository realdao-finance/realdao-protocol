pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./interfaces/PriceOracleInterface.sol";
import "./interfaces/EIP20Interface.sol";
import "./interfaces/RTokenInterface.sol";
import "./libraries/Strings.sol";
import "./libraries/SafeMath.sol";
import "./AuthBase.sol";

/**
 * @title Price oracle implementation based on centralized feed
 */

contract FeedPriceOracle is AuthBase {
  using SafeMath for uint256;

  address public admin;
  mapping(string => uint256) public assetPrices;

  event PricesUpdated(string[] symbols, uint256[] prices);

  /**
   * @notice Initialize the price oracle
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);
  }

  /**
   * @notice Get the underlying price of a rToken asset
   * @param rTokenAddr The rToken to get the underlying price of
   * @return The underlying asset price mantissa (scaled by 1e18)
   */
  function getUnderlyingPrice(address rTokenAddr) external view returns (uint256) {
    RTokenInterface rToken = RTokenInterface(rTokenAddr);
    string memory symbol = rToken.anchorSymbol();
    uint256 underlyingDecimals;

    if (Strings.equals(symbol, "USD")) {
      return 1e18;
    } else if (Strings.equals(symbol, "ETH")) {
      underlyingDecimals = 18;
    } else {
      underlyingDecimals = EIP20Interface(rToken.underlying()).decimals();
    }
    require(underlyingDecimals <= 18, "FeedPriceOracle/underlying decimals overflow");
    uint256 price = getPrice(symbol);
    return price.mul(10**(18 - underlyingDecimals));
  }

  /**
   * @notice Set the prices of anchor assets directly
   * @param symbols The anchor asset symbol, e.g. ETH, BTC
   * @param prices The asset prices to set
   */
  function setUnderlyingPrices(string[] calldata symbols, uint256[] calldata prices) external onlyCouncil {
    // FIXME check prams lenght
    for (uint256 i = 0; i < symbols.length; i++) {
      assetPrices[symbols[i]] = prices[i];
    }
    emit PricesUpdated(symbols, prices);
  }

  function getPrice(string memory symbol) internal view returns (uint256) {
    return assetPrices[symbol];
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_ORACLE;
  }
}
