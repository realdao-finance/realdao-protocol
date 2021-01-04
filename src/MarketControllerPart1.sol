pragma solidity ^0.6.0;

import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/PriceOracleInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./libraries/Exponential.sol";
import "./ErrorBase.sol";
import "./MarketControllerErrorCode.sol";

/**
 * @title RealDAO' MarketController Contract
 */
contract MarketControllerPart1 is Exponential, ErrorBase, MarketControllerErrorCode {
  MarketControllerInterface public controller;

  function bind(address _controller) external {
    expect(address(controller) == address(0), ERR_ALREADY_BOUND, "MarketController/controller parts already bound");
    controller = MarketControllerInterface(_controller);
  }

  /**
   * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
   * @dev Used in liquidation (called in rToken.liquidateBorrowFresh)
   * @param rTokenBorrowed The address of the borrowed rToken
   * @param rTokenCollateral The address of the collateral rToken
   * @param actualRepayAmount The amount of rTokenBorrowed underlying to convert into rTokenCollateral tokens
   * @return number of rTokenCollateral tokens to be seized in a liquidation
   */
  function liquidateCalculateSeizeTokens(
    address rTokenBorrowed,
    address rTokenCollateral,
    uint256 actualRepayAmount
  ) external view returns (uint256) {
    /* Read oracle prices for borrowed and collateral markets */
    PriceOracleInterface oracle = PriceOracleInterface(controller.getOracle());
    uint256 priceBorrowedMantissa = oracle.getUnderlyingPrice(rTokenBorrowed);
    uint256 priceCollateralMantissa = oracle.getUnderlyingPrice(rTokenCollateral);
    expect(priceBorrowedMantissa > 0, ERR_PRICE_ZERO, "MarketController/price of borrowed token is zero");
    expect(priceCollateralMantissa > 0, ERR_PRICE_ZERO, "MarketController/price of collateral token is zero");

    /*
     * Get the exchange rate and calculate the number of collateral tokens to seize:
     *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
     *  seizeTokens = seizeAmount / exchangeRate
     *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
     */
    uint256 exchangeRateMantissa = RTokenInterface(rTokenCollateral).exchangeRateCurrent();
    uint256 seizeTokens;
    Exp memory numerator;
    Exp memory denominator;
    Exp memory ratio;
    MathError mathErr;

    uint256 liquidationIncentiveMantissa = controller.liquidationIncentiveMantissa();
    (mathErr, numerator) = mulExp(liquidationIncentiveMantissa, priceBorrowedMantissa);
    checkMath(mathErr == MathError.NO_ERROR, ERR_LIQUIDATION_CALC, "MarketController/liquide seize calc 1");

    (mathErr, denominator) = mulExp(priceCollateralMantissa, exchangeRateMantissa);
    checkMath(mathErr == MathError.NO_ERROR, ERR_LIQUIDATION_CALC, "MarketController/liquide seize calc 2");

    (mathErr, ratio) = divExp(numerator, denominator);
    checkMath(mathErr == MathError.NO_ERROR, ERR_LIQUIDATION_CALC, "MarketController/liquide seize calc 3");

    (mathErr, seizeTokens) = mulScalarTruncate(ratio, actualRepayAmount);
    checkMath(mathErr == MathError.NO_ERROR, ERR_LIQUIDATION_CALC, "MarketController/liquide seize calc 4");

    return seizeTokens;
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
  ) external view returns (uint8) {
    // Shh - currently unused
    liquidator;
    rTokenCollateral;

    if (!controller.isLiquidating(rTokenBorrowed) && !controller.isLiquidating(rTokenCollateral)) {
      (, uint256 shortfall) = getHypotheticalAccountLiquidityInternal(borrower, address(0), 0, 0);
      checkBusiness(shortfall > 0, ERR_INSUFFICIENT_SHORTFALL, "MarketController/insufficient shortfall");

      uint256 closeFactorMantissa = controller.closeFactorMantissa();
      uint256 borrowBalance = RTokenInterface(rTokenBorrowed).borrowBalanceCurrent(borrower);
      (MathError mathErr, uint256 maxClose) = mulScalarTruncate(Exp({ mantissa: closeFactorMantissa }), borrowBalance);
      checkMath(mathErr == MathError.NO_ERROR, ERR_MAX_CLOSE_CALC, "MarketController/max close calculation failed");
      checkBusiness(repayAmount <= maxClose, ERR_TOO_MUCH_REPAY, "MarketController/too much repay");
    }
    return 0;
  }

  function getHypotheticalAccountLiquidity(
    address account,
    address rTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
  ) external view returns (uint256, uint256) {
    return getHypotheticalAccountLiquidityInternal(account, rTokenModify, redeemTokens, borrowAmount);
  }

  /**
   * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
   *  Note that `rTokenBalance` is the number of rTokens the account owns in the market,
   *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
   */
  struct AccountLiquidityLocalVars {
    uint256 sumCollateral;
    uint256 sumBorrowPlusEffects;
    uint256 rTokenBalance;
    uint256 borrowBalance;
    uint256 exchangeRateMantissa;
    uint256 oraclePriceMantissa;
    address[] assets;
    uint256[] collateralFactors;
    Exp collateralFactor;
    Exp exchangeRate;
    Exp oraclePrice;
    Exp tokensToDenom;
  }

  /**
   * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
   * @param rTokenModify The market to hypothetically redeem/borrow in
   * @param account The account to determine liquidity for
   * @param redeemTokens The number of tokens to hypothetically redeem
   * @param borrowAmount The amount of underlying to hypothetically borrow
   * @dev Note that we calculate the exchangeRateStored for each collateral rToken using stored data,
   *  without calculating accumulated interest.
   * @return (hypothetical account liquidity in excess of collateral requirements,
   *                    hypothetical account shortfall below collateral requirements)
   */
  function getHypotheticalAccountLiquidityInternal(
    address account,
    address rTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
  ) internal view returns (uint256, uint256) {
    AccountLiquidityLocalVars memory vars;
    MathError mErr;
    PriceOracleInterface oracle = PriceOracleInterface(controller.getOracle());

    vars.assets = controller.getAssetsIn(account);
    vars.collateralFactors = controller.getCollateralFactors(account);
    for (uint256 i = 0; i < vars.assets.length; i++) {
      RTokenInterface asset = RTokenInterface(vars.assets[i]);

      (vars.rTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
      if (vars.rTokenBalance == 0 && vars.borrowBalance == 0 && vars.assets[i] != rTokenModify) {
        continue;
      }
      vars.collateralFactor = Exp({ mantissa: vars.collateralFactors[i] });
      vars.exchangeRate = Exp({ mantissa: vars.exchangeRateMantissa });

      // Get the normalized price of the asset
      vars.oraclePriceMantissa = oracle.getUnderlyingPrice(address(asset));
      expect(vars.oraclePriceMantissa > 0, ERR_PRICE_ZERO, "MarketController/account liquidity get zero price");

      vars.oraclePrice = Exp({ mantissa: vars.oraclePriceMantissa });

      // Pre-compute a conversion factor from tokens -> ether (normalized price value)
      (mErr, vars.tokensToDenom) = mulExp3(vars.collateralFactor, vars.exchangeRate, vars.oraclePrice);
      checkMath(mErr == MathError.NO_ERROR, ERR_ACCOUNT_LIQUIDITY_CALC, "MarketController/account liquidity calc 1");

      // sumCollateral += tokensToDenom * rTokenBalance
      (mErr, vars.sumCollateral) = mulScalarTruncateAddUInt(vars.tokensToDenom, vars.rTokenBalance, vars.sumCollateral);
      checkMath(mErr == MathError.NO_ERROR, ERR_ACCOUNT_LIQUIDITY_CALC, "MarketController/account liquidity calc 2");

      // sumBorrowPlusEffects += oraclePrice * borrowBalance
      (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(
        vars.oraclePrice,
        vars.borrowBalance,
        vars.sumBorrowPlusEffects
      );
      checkMath(mErr == MathError.NO_ERROR, ERR_ACCOUNT_LIQUIDITY_CALC, "MarketController/account liquidity calc 3");

      // Calculate effects of interacting with rTokenModify
      if (address(asset) == rTokenModify) {
        // redeem effect
        // sumBorrowPlusEffects += tokensToDenom * redeemTokens
        (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(
          vars.tokensToDenom,
          redeemTokens,
          vars.sumBorrowPlusEffects
        );
        checkMath(mErr == MathError.NO_ERROR, ERR_ACCOUNT_LIQUIDITY_CALC, "MarketController/account liquidity calc 4");

        // borrow effect
        // sumBorrowPlusEffects += oraclePrice * borrowAmount
        (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(
          vars.oraclePrice,
          borrowAmount,
          vars.sumBorrowPlusEffects
        );
        checkMath(mErr == MathError.NO_ERROR, ERR_ACCOUNT_LIQUIDITY_CALC, "MarketController/account liquidity calc 5");
      }
    }

    // These are safe, as the underflow condition is checked first
    if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
      return (vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
    } else {
      return (0, vars.sumBorrowPlusEffects - vars.sumCollateral);
    }
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_CONTROLLER;
  }
}
