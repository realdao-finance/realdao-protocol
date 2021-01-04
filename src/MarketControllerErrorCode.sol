pragma solidity ^0.6.0;

contract MarketControllerErrorCode {
  uint8 constant ERR_MARKET_NOT_LISTED = 1;
  uint8 constant ERR_TOO_MANY_ASSETS = 2;
  uint8 constant ERR_INSUFFICIENT_LIQUIDITY = 3;
  uint8 constant ERR_INVALID_PARTS_LEN = 4;
  uint8 constant ERR_MARKET_SUSPENDED = 5;
  uint8 constant ERR_INVALID_LIQUIDATION_INCENTIVE = 6;
  uint8 constant ERR_TOKEN_ALREADY_LISTED = 7;
  uint8 constant ERR_INVALID_CLOSE_FACTOR = 8;
  uint8 constant ERR_INVALID_COLLATERAL_FACTOR = 9;
  uint8 constant ERR_PRICE_ZERO = 10;
  uint8 constant ERR_LIQUIDATION_CALC = 11;
  uint8 constant ERR_ACCOUNT_LIQUIDITY_CALC = 12;
  uint8 constant ERR_INSUFFICIENT_SHORTFALL = 13;
  uint8 constant ERR_MAX_CLOSE_CALC = 14;
  uint8 constant ERR_TOO_MUCH_REPAY = 15;
  uint8 constant ERR_ALREADY_BOUND = 16;
  uint8 constant ERR_MARKET_NOT_FOUND = 17;
  uint8 constant ERR_MARKET_NOT_CLOSING = 18;
  uint8 constant ERR_MARKET_NOT_LIQUIDATING = 19;
  uint8 constant ERR_MARKET_STATUS_NONE = 20;
}
