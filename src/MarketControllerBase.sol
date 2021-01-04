pragma solidity ^0.6.0;

import "./interfaces/PriceOracleInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./libraries/Exponential.sol";
import "./AuthBase.sol";
import "./RToken.sol";
import "./MarketControllerErrorCode.sol";

/**
 * @title RealDAO' MarketController Contract
 */
contract MarketControllerBase is AuthBase, Exponential, MarketControllerErrorCode {
  enum MarketState { None, Listed, Closing, Liquidating }
  struct Market {
    MarketState state;
    /**
     * @notice Multiplier representing the most one can borrow against their collateral in this market.
     *  For instance, 0.9 to allow borrowing 90% of collateral value.
     *  Must be between 0 and 1, and stored as a mantissa.
     */
    uint256 collateralFactorMantissa;
  }

  /**
   * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
   */
  uint256 public closeFactorMantissa;

  /**
   * @notice Multiplier representing the discount on collateral that a liquidator receives
   */
  uint256 public liquidationIncentiveMantissa;

  /**
   * @notice Default collateral factor
   */
  uint256 public defaultCollateralFactorMantissa;

  /**
   * @notice Max number of assets a single account can participate in (borrow or use as collateral)
   */
  uint256 public maxAssets;

  /**
   * @notice Official mapping of rTokens -> Market metadata
   * @dev Used e.g. to determine if a market is supported
   */
  mapping(address => Market) public markets;

  bool public suspended;

  /// @notice A list of all markets
  address[] public allMarkets;

  // closeFactorMantissa must be strictly greater than this value
  uint256 constant closeFactorMinMantissa = 0.05e18; // 0.05

  // closeFactorMantissa must not exceed this value
  uint256 constant closeFactorMaxMantissa = 0.9e18; // 0.9

  // No collateralFactorMantissa may exceed this value
  uint256 constant collateralFactorMaxMantissa = 0.9e18; // 0.9

  // liquidationIncentiveMantissa must be no less than this value
  uint256 constant liquidationIncentiveMinMantissa = 1.0e18; // 1.0

  // liquidationIncentiveMantissa must be no greater than this value
  uint256 constant liquidationIncentiveMaxMantissa = 1.5e18; // 1.5

  /// @notice Emitted when an admin supports a market
  event MarketListed(address rToken);

  /// @notice Emitted when close factor is changed by admin
  event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);

  /// @notice Emitted when a collateral factor is changed by admin
  event NewCollateralFactor(address rToken, uint256 oldCollateralFactorMantissa, uint256 newCollateralFactorMantissa);

  /// @notice Emitted when liquidation incentive is changed by admin
  event NewLiquidationIncentive(uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa);

  /// @notice Emitted when maxAssets is changed by admin
  event NewMaxAssets(uint256 oldMaxAssets, uint256 newMaxAssets);

  /// @notice Emitted when an market is suspended
  event MarketSuspended(bool isCurrentSuspended);

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_CONTROLLER;
  }
}
