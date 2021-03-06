pragma solidity ^0.6.0;

import "./libraries/SafeMath.sol";
import "./AuthBase.sol";

/**
 * @title RealDAO' InterestRateModel
 * @notice Enabling updateable parameters.
 */
contract InterestRateModel is AuthBase {
  using SafeMath for uint256;

  /**
   * @notice The multiplier of utilization rate that gives the slope of the interest rate
   */
  uint256 public multiplierPerBlock;

  /**
   * @notice The base interest rate which is the y-intercept when utilization rate is 0
   */
  uint256 public baseRatePerBlock;

  /**
   * @notice The multiplierPerBlock after hitting a specified utilization point
   */
  uint256 public jumpMultiplierPerBlock;

  /**
   * @notice The utilization point at which the jump multiplier is applied
   */
  uint256 public kink;

  event NewInterestParams(
    uint256 baseRatePerBlock,
    uint256 multiplierPerBlock,
    uint256 jumpMultiplierPerBlock,
    uint256 kink
  );

  /**
   * @notice Construct an interest rate model
   * @param _orchestrator The address of the Orchestrator
   */
  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);
    uint256 baseRatePerYear = 0.01e18;
    uint256 multiplierPerYear = 0.05e18;
    uint256 jumpMultiplierPerYear = 1.09e18;
    uint256 _kink = 0.8e18;
    updateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, _kink);
  }

  /**
   * @notice Update the parameters of the interest rate model (only callable by admin, i.e. Timelock)
   * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
   * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
   * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
   * @param _kink The utilization point at which the jump multiplier is applied
   */
  function updateModel(
    uint256 baseRatePerYear,
    uint256 multiplierPerYear,
    uint256 jumpMultiplierPerYear,
    uint256 _kink
  ) external onlyCouncil {
    updateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, _kink);
  }

  /**
   * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @param reserves The amount of reserves in the market (currently unused)
   * @return The utilization rate as a mantissa between [0, 1e18]
   */
  function utilizationRate(
    uint256 cash,
    uint256 borrows,
    uint256 reserves
  ) public pure returns (uint256) {
    // Utilization rate is 0 when there are no borrows
    if (borrows == 0) {
      return 0;
    }

    return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
  }

  /**
   * @notice Calculates the current borrow rate per block, with the error code expected by the market
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @param reserves The amount of reserves in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getBorrowRate(
    uint256 cash,
    uint256 borrows,
    uint256 reserves
  ) external view returns (uint256) {
    return getBorrowRateInternal(cash, borrows, reserves);
  }

  /**
   * @notice Calculates the current supply rate per block
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @param reserves The amount of reserves in the market
   * @param reserveFactorMantissa The current reserve factor for the market
   * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getSupplyRate(
    uint256 cash,
    uint256 borrows,
    uint256 reserves,
    uint256 reserveFactorMantissa
  ) external view returns (uint256) {
    uint256 oneMinusReserveFactor = uint256(1e18).sub(reserveFactorMantissa);
    uint256 borrowRate = getBorrowRateInternal(cash, borrows, reserves);
    uint256 rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
    return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
  }

  /**
   * @notice Calculates the current supply rate per block for DOL market
   * @param cash The amount of cash in the market
   * @param borrows The amount of borrows in the market
   * @param reserves The amount of reserves in the market
   * @param reserveFactorMantissa The current reserve factor for the market
   * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getSupplyRate2(
    uint256 cash,
    uint256 borrows,
    uint256 reserves,
    uint256 reserveFactorMantissa
  ) external view returns (uint256) {
    uint256 oneMinusReserveFactor = uint256(1e18).sub(reserveFactorMantissa);
    uint256 borrowRate = getBorrowRateInternal(cash, borrows, reserves);
    return borrowRate.mul(oneMinusReserveFactor).div(1e18);
  }

  /**
   * @notice Internal function to update the parameters of the interest rate model
   * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
   * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
   * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
   * @param _kink The utilization point at which the jump multiplier is applied
   */
  function updateModelInternal(
    uint256 baseRatePerYear,
    uint256 multiplierPerYear,
    uint256 jumpMultiplierPerYear,
    uint256 _kink
  ) internal {
    baseRatePerBlock = baseRatePerYear.div(blocksPerYear);
    multiplierPerBlock = (multiplierPerYear.mul(1e18)).div(blocksPerYear.mul(_kink));
    jumpMultiplierPerBlock = jumpMultiplierPerYear.div(blocksPerYear);
    kink = _kink;

    emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
  }

  function getBorrowRateInternal(
    uint256 cash,
    uint256 borrows,
    uint256 reserves
  ) internal view returns (uint256) {
    uint256 util = utilizationRate(cash, borrows, reserves);

    if (util <= kink) {
      return util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
    } else {
      uint256 normalRate = kink.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
      uint256 excessUtil = util.sub(kink);
      return excessUtil.mul(jumpMultiplierPerBlock).div(1e18).add(normalRate);
    }
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_INTEREST_RATE;
  }
}
