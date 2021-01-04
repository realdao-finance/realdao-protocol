pragma solidity ^0.6.0;

import "./interfaces/ChainlinkAggregatorV3Interface.sol";
import "./interfaces/EIP20Interface.sol";
import "./interfaces/RTokenInterface.sol";
import "./interfaces/PriceOracleInterface.sol";
import "./libraries/Strings.sol";
import "./libraries/SafeMath.sol";
import "./AuthBase.sol";

/**
 * @title Price oracle implementation based on chainlink
 */
contract ChainlinkPriceOracle is AuthBase, PriceOracleInterface {
  using SafeMath for uint256;

  mapping(string => address) priceFeeds;

  uint8 constant ERR_UNDERLYING_DECIMALS_TOO_BIG = 1;
  uint8 constant ERR_SET_PRICE_DEV_ONLY = 2;

  /**
   * @notice Initialize the price oracle
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);

    // Hard code the price feed address in Mainnet
    setPriceFeedAddressInternal("ETH", 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
  }

  /**
   * @notice Get the underlying price of a rToken asset
   * @param rTokenAddr The rToken to get the underlying price of
   * @return The underlying asset price mantissa (scaled by 1e18)
   */
  function getUnderlyingPrice(address rTokenAddr) external override view returns (uint256) {
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

    expect(
      underlyingDecimals <= 18,
      ERR_UNDERLYING_DECIMALS_TOO_BIG,
      "ChainlinkPriceOracle/underlying decimals too big"
    );
    uint256 price = getPrice(symbol);
    return price.mul(10**(18 - underlyingDecimals));
  }

  /**
   * @notice Set the address of the price feed contract
   * @param symbol The anchor asset symbol, e.g. ETH, BTC
   * @param addr The contract address
   */
  function setPriceFeedAddress(string calldata symbol, address addr) external override onlyCouncil {
    setPriceFeedAddressInternal(symbol, addr);
  }

  /**
   * @notice Set the price of anchor asset directly
   *  @dev This is a mock interface used in dev network
   * @param symbol The anchor asset symbol, e.g. ETH, BTC
   * @param price The asset price
   */
  function setUnderlyingPrice(string calldata symbol, uint256 price) external override {
    symbol;
    price;
    check(false, ERR_TYPE_ENV, ERR_SET_PRICE_DEV_ONLY, "ChainlinkPriceOracle/only supported in dev network");
  }

  function setPriceFeedAddressInternal(string memory symbol, address addr) internal {
    priceFeeds[symbol] = addr;
    emit NewPriceFeedAddress(msg.sender, symbol, addr);
  }

  function getPrice(string memory symbol) internal view returns (uint256) {
    address priceFeed = priceFeeds[symbol];
    if (priceFeed == address(0)) {
      return 0;
    }
    (, int256 price, , , ) = ChainlinkAggregatorV3Interface(priceFeed).latestRoundData();
    return uint256(price);
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_ORACLE;
  }
}
