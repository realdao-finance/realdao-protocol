pragma solidity ^0.6.0;

import "./interfaces/DistributorInterface.sol";
import "./MarketControllerBase.sol";
import "./MarketControllerPart1.sol";

/**
 * @title RealDAO' MarketController Contract
 */
contract MarketController is MarketControllerBase {
  MarketControllerPart1 public part1;

  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);

    closeFactorMantissa = 0.5e18; // 0.5
    liquidationIncentiveMantissa = 1.08e18; // 1.08
    defaultCollateralFactorMantissa = 0.75e18; // 0.75
    maxAssets = 256;
  }

  function bind(address[] calldata _parts) external {
    checkParams(_parts.length == 1, ERR_INVALID_PARTS_LEN, "MarketController/invalid parts length");
    part1 = MarketControllerPart1(_parts[0]);
    part1.bind(address(this));
  }

  function getOracle() external view returns (address) {
    return orchestrator.getOracle();
  }

  /**
   * @notice Returns the assets an account has entered
   * @param account The address of the account to pull assets for
   * @return A dynamic list with the assets the account has entered
   */
  function getAssetsIn(address account) external view returns (address[] memory) {
    // Deprecate the enterMarkets feature
    // Users will enter to all listed markets automatically once they use the protocol
    account;
    return allMarkets;
  }

  function getAllMarkets() external view returns (address[] memory) {
    return allMarkets;
  }

  function getMarket(address rToken) external view returns (uint256, uint256) {
    Market memory m = markets[rToken];
    return (uint256(m.state), m.collateralFactorMantissa);
  }

  function getCollateralFactors(address account) external view returns (uint256[] memory) {
    account;
    uint256 len = allMarkets.length;
    uint256[] memory collateralFactors = new uint256[](len);
    for (uint256 i = 0; i < len; i++) {
      collateralFactors[i] = markets[allMarkets[i]].collateralFactorMantissa;
    }
    return collateralFactors;
  }

  function isListedMarket(address rToken) external view returns (bool) {
    return markets[rToken].state == MarketState.Listed;
  }

  function isLiquidating(address rToken) external view returns (bool) {
    return markets[rToken].state == MarketState.Liquidating;
  }

  /*** Policy Hooks ***/

  /**
   * @notice Checks if the account should be allowed to mint tokens in the given market
   * @param rToken The market to verify the mint against
   * @param minter The account which would get the minted tokens
   * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
   * @return 0 if the mint is allowed, otherwise a semi-opaque error code
   */
  function mintAllowed(
    address rToken,
    address minter,
    uint256 mintAmount
  ) external view returns (uint8) {
    // Shh - currently unused
    mintAmount;
    minter;

    MarketState state = markets[rToken].state;
    checkBusiness(state == MarketState.Listed, ERR_MARKET_NOT_LISTED, "MarketController/market is not listed");
    return generalCheck(rToken);
  }

  /**
   * @notice Checks if the account should be allowed to redeem tokens in the given market
   * @param rToken The market to verify the redeem against
   * @param redeemer The account which would redeem the tokens
   * @param redeemTokens The number of rTokens to exchange for the underlying asset in the market
   * @return 0 if the redeem is allowed, otherwise a semi-opaque error code
   */
  function redeemAllowed(
    address rToken,
    address redeemer,
    uint256 redeemTokens
  ) external view returns (uint8) {
    return redeemAllowedInternal(rToken, redeemer, redeemTokens);
  }

  /**
   * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
   * @param rToken The market to verify the borrow against
   * @param borrower The account which would borrow the asset
   * @param borrowAmount The amount of underlying the account would borrow
   * @return 0 if the borrow is allowed, otherwise a semi-opaque error code
   */
  function borrowAllowed(
    address rToken,
    address borrower,
    uint256 borrowAmount
  ) external view returns (uint8) {
    uint8 err = generalCheck(rToken);
    if (err != 0) return err;

    MarketState state = markets[rToken].state;
    checkBusiness(state == MarketState.Listed, ERR_MARKET_NOT_LISTED, "MarketController/token is not listed");

    (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(borrower, rToken, 0, borrowAmount);
    checkBusiness(shortfall == 0, ERR_INSUFFICIENT_LIQUIDITY, "MarketController/insufficient liquidity");
    return 0;
  }

  /**
   * @notice Checks if the account should be allowed to repay a borrow in the given market
   * @param rToken The market to verify the repay against
   * @param payer The account which would repay the asset
   * @param borrower The account which would borrowed the asset
   * @param repayAmount The amount of the underlying asset the account would repay
   * @return 0 if the repay is allowed, otherwise a semi-opaque error code
   */
  function repayBorrowAllowed(
    address rToken,
    address payer,
    address borrower,
    uint256 repayAmount
  ) external view returns (uint8) {
    // Shh - currently unused
    payer;
    borrower;
    repayAmount;

    checkBusiness(
      markets[rToken].state != MarketState.None,
      ERR_MARKET_STATUS_NONE,
      "MarketController/repay in none state market"
    );

    return generalCheck(rToken);
  }

  /**
   * @notice Checks if the liquidation should be allowed to occur
   * @param rTokenBorrowed Asset which was borrowed by the borrower
   * @param rTokenCollateral Asset which was used as collateral and will be seized
   * @param liquidator The address repaying the borrow and seizing the collateral
   * @param borrower The address of the borrower
   * @param repayAmount The amount of underlying being repaid
   */
  function liquidateBorrowAllowed(
    address rTokenBorrowed,
    address rTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount
  ) external view returns (uint256) {
    checkBusiness(
      markets[rTokenCollateral].state != MarketState.None,
      ERR_MARKET_STATUS_NONE,
      "MarketController/liquidating collateral token state is none"
    );
    checkBusiness(
      markets[rTokenBorrowed].state != MarketState.None,
      ERR_MARKET_STATUS_NONE,
      "MarketController/liquidating borrowed token state is none"
    );
    return part1.liquidateBorrowAllowed(rTokenBorrowed, rTokenCollateral, liquidator, borrower, repayAmount);
  }

  /**
   * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
   * @dev Used in liquidation (called in rToken.liquidateBorrowFresh)
   * @param rTokenBorrowed The address of the borrowed rToken
   * @param rTokenCollateral The address of the collateral rToken
   * @param actualRepayAmount The amount of rTokenBorrowed underlying to convert into rTokenCollateral tokens
   * @return ( number of rTokenCollateral tokens to be seized in a liquidation)
   */
  function liquidateCalculateSeizeTokens(
    address rTokenBorrowed,
    address rTokenCollateral,
    uint256 actualRepayAmount
  ) external view returns (uint256) {
    return part1.liquidateCalculateSeizeTokens(rTokenBorrowed, rTokenCollateral, actualRepayAmount);
  }

  /**
   * @notice Checks if the seizing of assets should be allowed to occur
   * @param rTokenCollateral Asset which was used as collateral and will be seized
   * @param rTokenBorrowed Asset which was borrowed by the borrower
   * @param liquidator The address repaying the borrow and seizing the collateral
   * @param borrower The address of the borrower
   * @param seizeTokens The number of collateral tokens to seize
   */
  function seizeAllowed(
    address rTokenCollateral,
    address rTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external view returns (uint8) {
    // Shh - currently unused
    seizeTokens;
    liquidator;
    borrower;

    checkBusiness(!suspended, ERR_MARKET_SUSPENDED, "MarketController/market is suspended");
    checkBusiness(
      markets[rTokenCollateral].state != MarketState.None,
      ERR_MARKET_STATUS_NONE,
      "MarketController/seizing collateral token state is none"
    );
    checkBusiness(
      markets[rTokenBorrowed].state != MarketState.None,
      ERR_MARKET_STATUS_NONE,
      "MarketController/seizing borrowed token state is none"
    );
    return 0;
  }

  /**
   * @notice Checks if the account should be allowed to transfer tokens in the given market
   * @param rToken The market to verify the transfer against
   * @param src The account which sources the tokens
   * @param dst The account which receives the tokens
   * @param transferTokens The number of rTokens to transfer
   * @return 0 if the transfer is allowed, otherwise a semi-opaque error code
   */
  function transferAllowed(
    address rToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external view returns (uint256) {
    // Currently the only consideration is whether or not
    //  the src is allowed to redeem this many tokens
    dst;
    return redeemAllowedInternal(rToken, src, transferTokens);
  }

  /**
   * @notice Determine the current account liquidity wrt collateral requirements
   * @return (account liquidity in excess of collateral requirements,
   *                    account shortfall below collateral requirements)
   */
  function getAccountLiquidity(address account) external view returns (uint256, uint256) {
    return getHypotheticalAccountLiquidityInternal(account, address(0), 0, 0);
  }

  //============================================================================
  // Governance methods
  //============================================================================

  /**
   * @notice Sets maxAssets which controls how many markets can be entered
   * @dev Admin function to set maxAssets
   * @param newMaxAssets New max assets
   */
  function setMaxAssets(uint256 newMaxAssets) external onlyCouncil {
    uint256 oldMaxAssets = maxAssets;
    maxAssets = newMaxAssets;
    emit NewMaxAssets(oldMaxAssets, newMaxAssets);
  }

  /**
   * @notice Sets liquidationIncentive
   * @dev Admin function to set liquidationIncentive
   * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
   */
  function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external onlyCouncil {
    // Check de-scaled min <= newLiquidationIncentive <= max
    checkParams(
      newLiquidationIncentiveMantissa >= liquidationIncentiveMinMantissa,
      ERR_INVALID_LIQUIDATION_INCENTIVE,
      "MarketController/set for liquidation incentive too small"
    );
    checkParams(
      newLiquidationIncentiveMantissa <= liquidationIncentiveMaxMantissa,
      ERR_INVALID_LIQUIDATION_INCENTIVE,
      "MarketController/set for liquidation incentive too large"
    );
    emit NewLiquidationIncentive(liquidationIncentiveMantissa, newLiquidationIncentiveMantissa);
    liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;
  }

  /**
   * @notice Add the market to the markets mapping and set it as listed
   * @dev Admin function to set Listed and add support for the market
   * @param rToken The address of the market (token) to list
   */
  function supportMarket(address rToken) external onlyCouncil {
    checkBusiness(
      markets[rToken].state == MarketState.None,
      ERR_TOKEN_ALREADY_LISTED,
      "MarketController/token already listed"
    );

    markets[rToken] = Market({ state: MarketState.Listed, collateralFactorMantissa: defaultCollateralFactorMantissa });
    allMarkets.push(rToken);
    emit MarketListed(rToken);
  }

  function closeMarket(address rToken) external onlyCouncil {
    Market storage market = markets[rToken];
    checkParams(market.state == MarketState.Listed, ERR_MARKET_NOT_LISTED, "MarketController/close not listed market");
    DistributorInterface(orchestrator.getDistributor()).closeLendingPool(rToken);
    market.state = MarketState.Closing;
  }

  function liquidateMarket(address rToken) external onlyCouncil {
    Market storage market = markets[rToken];
    checkParams(market.state == MarketState.Closing, ERR_MARKET_NOT_CLOSING, "MarketController/market is not closing");
    market.state = MarketState.Liquidating;
  }

  function removeMarket(address rToken) external onlyCouncil {
    checkParams(
      markets[rToken].state == MarketState.Liquidating,
      ERR_MARKET_NOT_LIQUIDATING,
      "MarketController/market is not liquidating"
    );
    uint256 pos = allMarkets.length;
    uint256 len = allMarkets.length;
    for (uint256 i = 0; i < len; i++) {
      if (allMarkets[i] == rToken) {
        pos = i;
        break;
      }
    }
    expect(pos < len, ERR_MARKET_NOT_FOUND, "MarketController/market to remove not found");
    allMarkets[pos] = allMarkets[len - 1];
    allMarkets.pop();
    delete markets[rToken];
  }

  function toogleSuspension() external onlyCouncil {
    suspended = !suspended;
    emit MarketSuspended(suspended);
  }

  /**
   * @notice Sets the closeFactor used when liquidating borrows
   * @dev Admin function to set closeFactor
   * @param newCloseFactorMantissa New close factor, scaled by 1e18
   */
  function setCloseFactor(uint256 newCloseFactorMantissa) external onlyCouncil {
    checkParams(
      newCloseFactorMantissa >= closeFactorMinMantissa,
      ERR_INVALID_CLOSE_FACTOR,
      "MarketController/set for close factor too samll"
    );
    checkParams(
      newCloseFactorMantissa <= closeFactorMaxMantissa,
      ERR_INVALID_CLOSE_FACTOR,
      "MarketController/set for close factor too large"
    );

    emit NewCloseFactor(closeFactorMantissa, closeFactorMantissa);
    closeFactorMantissa = newCloseFactorMantissa;
  }

  /**
   * @notice Sets the collateralFactor for a market
   * @dev Admin function to set per-market collateralFactor
   * @param rToken The market to set the factor on
   * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
   */
  function setCollateralFactor(address rToken, uint256 newCollateralFactorMantissa) external onlyCouncil {
    checkParams(
      newCollateralFactorMantissa <= collateralFactorMaxMantissa,
      ERR_INVALID_COLLATERAL_FACTOR,
      "MarketController/set for collteral factor too large"
    );
    Market storage market = markets[rToken];
    checkBusiness(
      market.state == MarketState.Listed,
      ERR_MARKET_NOT_LISTED,
      "MarketController/set collateral factor for market that not listed"
    );
    emit NewCollateralFactor(rToken, market.collateralFactorMantissa, newCollateralFactorMantissa);
    market.collateralFactorMantissa = newCollateralFactorMantissa;
  }

  //============================================================================
  // Internal methods
  //============================================================================
  function generalCheck(address rToken) internal view returns (uint8) {
    rToken;
    checkBusiness(!suspended, ERR_MARKET_SUSPENDED, "MarketController/market is suspended");
    return 0;
  }

  function redeemAllowedInternal(
    address rToken,
    address redeemer,
    uint256 redeemTokens
  ) internal view returns (uint8) {
    uint8 err = generalCheck(rToken);
    if (err != 0) return err;

    MarketState state = markets[rToken].state;
    checkBusiness(
      state != MarketState.None,
      ERR_MARKET_STATUS_NONE,
      "MarketController/redeem or transfer none state rToken"
    );

    (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, rToken, redeemTokens, 0);
    checkBusiness(shortfall == 0, ERR_INSUFFICIENT_LIQUIDITY, "MarketController/insufficient liquidity");
    return 0;
  }

  function getHypotheticalAccountLiquidityInternal(
    address account,
    address rTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
  ) internal view returns (uint256, uint256) {
    return part1.getHypotheticalAccountLiquidity(account, rTokenModify, redeemTokens, borrowAmount);
  }
}
