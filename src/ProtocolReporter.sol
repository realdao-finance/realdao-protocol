pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./interfaces/EIP20Interface.sol";
import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/PriceOracleInterface.sol";
import "./interfaces/OrchestratorInterface.sol";
import "./libraries/Strings.sol";
import "./RErc20.sol";
import "./RToken.sol";
import "./RDS.sol";

/**
 * @title ProtocolReporter contract
 */
contract ProtocolReporter {
  using Strings for *;

  struct MarketInfo {
    address rToken;
    string symbol;
    string name;
    string underlyingSymbol;
    string anchorSymbol;
    uint256 exchangeRateCurrent;
    uint256 supplyRatePerBlock;
    uint256 borrowRatePerBlock;
    uint256 reserveFactorMantissa;
    uint256 totalBorrows;
    uint256 totalReserves;
    uint256 totalSupply;
    uint256 totalCash;
    uint256 state;
    uint256 collateralFactorMantissa;
    address underlyingAssetAddress;
    uint256 rTokenDecimals;
    uint256 underlyingDecimals;
  }

  struct RTokenBalances {
    address rToken;
    uint256 balanceOf;
    uint256 borrowBalanceCurrent;
    uint256 balanceOfUnderlying;
    uint256 tokenBalance;
    uint256 tokenAllowance;
    uint256 underlyingDecimals;
    string underlyingSymbol;
  }

  struct RTokenUnderlyingPrice {
    address rToken;
    uint256 underlyingPrice;
    string anchorSymbol;
  }

  struct AccountLimits {
    address[] markets;
    uint256 liquidity;
    uint256 shortfall;
  }

  OrchestratorInterface public orchestrator;

  /**
   * @notice Initialize ProtocolReporter contract
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) external {
    require(address(orchestrator) == address(0), "ProtocolReporter/already initialized");
    orchestrator = OrchestratorInterface(_orchestrator);
  }

  /**
   * @notice Query the market info by a specific token address
   * @param rTokenAddr Address of the money market to query
   * @return MarketInfo object
   */
  function getMarketInfo(address rTokenAddr) public view returns (MarketInfo memory) {
    RToken rToken = RToken(rTokenAddr);
    uint256 exchangeRateCurrent = rToken.exchangeRateCurrent();
    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    (uint256 state, uint256 collateralFactorMantissa) = controller.getMarket(address(rToken));
    address underlyingAssetAddress;
    uint256 underlyingDecimals;
    string memory symbol = rToken.symbol();
    string memory underlyingSymbol;

    if (Strings.equals(symbol, "rETH")) {
      underlyingAssetAddress = address(0);
      underlyingDecimals = 18;
      underlyingSymbol = "ETH";
    } else {
      RErc20 rErc20 = RErc20(address(rToken));
      underlyingAssetAddress = rErc20.underlying();
      underlyingDecimals = EIP20Interface(rErc20.underlying()).decimals();
      underlyingSymbol = EIP20Interface(rErc20.underlying()).symbol();
    }

    return
      MarketInfo({
        rToken: address(rToken),
        symbol: symbol,
        name: rToken.name(),
        underlyingSymbol: underlyingSymbol,
        anchorSymbol: rToken.anchorSymbol(),
        exchangeRateCurrent: exchangeRateCurrent,
        supplyRatePerBlock: rToken.supplyRatePerBlock(),
        borrowRatePerBlock: rToken.borrowRatePerBlock(),
        reserveFactorMantissa: rToken.reserveFactorMantissa(),
        totalBorrows: rToken.totalBorrows(),
        totalReserves: rToken.totalReserves(),
        totalSupply: rToken.totalSupply(),
        totalCash: rToken.getCash(),
        state: state,
        collateralFactorMantissa: collateralFactorMantissa,
        underlyingAssetAddress: underlyingAssetAddress,
        rTokenDecimals: rToken.decimals(),
        underlyingDecimals: underlyingDecimals
      });
  }

  /**
   * @notice Query the market info of all the markets in the protocol
   * @return Array of MarketInfo object
   */
  function getAllMarketInfo() external view returns (MarketInfo[] memory) {
    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    address[] memory rTokens = controller.getAllMarkets();
    MarketInfo[] memory res = new MarketInfo[](rTokens.length);
    for (uint256 i = 0; i < rTokens.length; i++) {
      res[i] = getMarketInfo(rTokens[i]);
    }
    return res;
  }

  /**
   * @notice Query balance info for a user
   * @param rTokenAddr Address of the money market to query
   * @param account Address of the queried user
   * @return RTokenBalances object
   */
  function getRTokenBalances(address rTokenAddr, address payable account) public view returns (RTokenBalances memory) {
    RToken rToken = RToken(rTokenAddr);
    uint256 balanceOf = rToken.balanceOf(account);
    uint256 borrowBalanceCurrent = rToken.borrowBalanceCurrent(account);
    uint256 balanceOfUnderlying = rToken.balanceOfUnderlying(account);
    uint256 tokenBalance;
    uint256 tokenAllowance;
    uint256 underlyingDecimals;
    string memory underlyingSymbol;

    if (Strings.equals(rToken.symbol(), "rETH")) {
      tokenBalance = account.balance;
      tokenAllowance = account.balance;
      underlyingSymbol = "ETH";
      underlyingDecimals = 18;
    } else {
      RErc20 rErc20 = RErc20(address(rToken));
      EIP20Interface underlying = EIP20Interface(rErc20.underlying());
      tokenBalance = underlying.balanceOf(account);
      tokenAllowance = underlying.allowance(account, address(rToken));
      underlyingSymbol = underlying.symbol();
      underlyingDecimals = underlying.decimals();
    }

    return
      RTokenBalances({
        rToken: address(rToken),
        balanceOf: balanceOf,
        borrowBalanceCurrent: borrowBalanceCurrent,
        balanceOfUnderlying: balanceOfUnderlying,
        tokenBalance: tokenBalance,
        tokenAllowance: tokenAllowance,
        underlyingDecimals: underlyingDecimals,
        underlyingSymbol: underlyingSymbol
      });
  }

  /**
   * @notice Query balance info of all the markets for a user
   * @param account Address of the queried user
   * @return Array of RTokenBalances object
   */
  function getAllRTokenBalances(address payable account) external view returns (RTokenBalances[] memory) {
    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    address[] memory rTokens = controller.getAllMarkets();
    RTokenBalances[] memory res = new RTokenBalances[](rTokens.length);
    for (uint256 i = 0; i < rTokens.length; i++) {
      res[i] = getRTokenBalances(rTokens[i], account);
    }
    return res;
  }

  /**
   * @notice Get the underlying price of a rToken asset
   * @param rTokenAddr The rToken to get the underlying price of
   * @return RTokenUnderlyingPrice object
   */
  function getUnderlyingPrice(address rTokenAddr) public view returns (RTokenUnderlyingPrice memory) {
    RToken rToken = RToken(rTokenAddr);
    PriceOracleInterface oracle = PriceOracleInterface(orchestrator.getOracle());
    uint256 price = oracle.getUnderlyingPrice(rTokenAddr);
    return RTokenUnderlyingPrice({ rToken: rTokenAddr, anchorSymbol: rToken.anchorSymbol(), underlyingPrice: price });
  }

  /**
   * @notice Get the underlying prices of rToken assets from all markets
   * @return Array of RTokenUnderlyingPrice object
   */
  function getUnderlyingPrices() external view returns (RTokenUnderlyingPrice[] memory) {
    MarketControllerInterface controller = MarketControllerInterface(orchestrator.getMarketController());
    address[] memory rTokens = controller.getAllMarkets();
    RTokenUnderlyingPrice[] memory res = new RTokenUnderlyingPrice[](rTokens.length);
    for (uint256 i = 0; i < rTokens.length; i++) {
      res[i] = getUnderlyingPrice(rTokens[i]);
    }
    return res;
  }
}
