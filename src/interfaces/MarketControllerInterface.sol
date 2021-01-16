pragma solidity ^0.6.0;

interface MarketControllerInterface {
  function initialize(address orchestrator) external;

  function bind(address lib) external;

  function isLiquidating(address rToken) external view returns (bool);

  function liquidationIncentiveMantissa() external view returns (uint256);

  function closeFactorMantissa() external view returns (uint256);

  function getOracle() external view returns (address);

  function getAllMarkets() external view returns (address[] memory);

  function getMarket(address rToken) external view returns (uint256, uint256);

  function getAssetsIn(address account) external view returns (address[] memory);

  function getCollateralFactors(address account) external view returns (uint256[] memory);

  function getAccountLiquidity(address) external view returns (uint256, uint256);

  function getHypotheticalAccountLiquidity(
    address account,
    address rTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
  ) external view returns (uint256, uint256);

  function mintAllowed(
    address rToken,
    address minter,
    uint256 mintAmount
  ) external view returns (uint8);

  function redeemAllowed(
    address rToken,
    address redeemer,
    uint256 redeemTokens
  ) external view returns (uint8);

  function borrowAllowed(
    address rToken,
    address borrower,
    uint256 borrowAmount
  ) external view returns (uint8);

  function repayBorrowAllowed(
    address rToken,
    address payer,
    address borrower,
    uint256 repayAmount
  ) external view returns (uint8);

  function liquidateBorrowAllowed(
    address rTokenBorrowed,
    address rTokenCollateral,
    address liquidator,
    address borrower,
    uint256 repayAmount
  ) external view returns (uint8);

  function seizeAllowed(
    address rTokenCollateral,
    address rTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external view returns (uint8);

  function transferAllowed(
    address rToken,
    address src,
    address dst,
    uint256 transferTokens
  ) external view returns (uint8);

  function liquidateCalculateSeizeTokens(
    address rTokenBorrowed,
    address rTokenCollateral,
    uint256 repayAmount
  ) external view returns (uint256);

  function supportMarket(address rToken) external;

  function setMaxAssets(uint256 newMaxAssets) external;

  function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external;

  function setMarketPaused(bool state) external;

  function setCloseFactor(uint256 newCloseFactorMantissa) external;

  function setCollateralFactor(address rToken, uint256 newCollateralFactorMantissa) external;
}
