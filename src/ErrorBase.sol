pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./libraries/Strings.sol";

abstract contract ErrorBase {
  using Strings for *;

  struct Error {
    uint8 domain;
    uint8 etype;
    uint8 detail;
    string context;
  }

  uint8 constant ERR_DOMAIN_UNKNOW = 10;
  uint8 constant ERR_DOMAIN_RTOKEN = 11;
  uint8 constant ERR_DOMAIN_CONTROLLER = 12;
  uint8 constant ERR_DOMAIN_DISTRIBUTOR = 13;
  uint8 constant ERR_DOMAIN_ORACLE = 14;
  uint8 constant ERR_DOMAIN_INTEREST_RATE = 15;
  uint8 constant ERR_DOMAIN_COUNCIL = 16;
  uint8 constant ERR_DOMAIN_DEMOCRACY = 17;
  uint8 constant ERR_DOMAIN_ORCHESTRATOR = 18;

  uint8 constant ERR_TYPE_PARAMETER = 1;
  uint8 constant ERR_TYPE_MATH = 2;
  uint8 constant ERR_TYPE_AUTH = 3;
  uint8 constant ERR_TYPE_BUSINESS = 4;
  uint8 constant ERR_TYPE_UNEXPECTED = 5;
  uint8 constant ERR_TYPE_ENV = 6;
  uint8 constant ERR_TYPE_EXTERNAL_SERVICE = 7;

  function errorDomain() internal virtual pure returns (uint8);

  function fail(
    uint8 etype,
    uint8 detail,
    string memory context
  ) internal pure returns (Error memory) {
    uint8 domain = errorDomain();
    return Error({ domain: domain, etype: etype, detail: detail, context: context });
  }

  function fail(
    uint8 domain,
    uint8 etype,
    uint8 detail,
    string memory context
  ) internal pure returns (Error memory) {
    return Error({ domain: domain, etype: etype, detail: detail, context: context });
  }

  function success() internal pure returns (Error memory) {
    return Error({ domain: 0, etype: 0, detail: 0, context: "" });
  }

  function errorCode(
    uint8 domain,
    uint8 etype,
    uint8 detail
  ) internal pure returns (uint256) {
    return uint256(domain) * 100000 + uint256(etype) * 1000 + uint256(detail);
  }

  function errorCode(uint8 etype, uint8 detail) internal pure returns (uint256) {
    uint8 domain = errorDomain();
    return errorCode(domain, etype, detail);
  }

  function toCode(Error memory err) internal pure returns (uint256) {
    return errorCode(err.domain, err.etype, err.detail);
  }

  function toString(Error memory err) internal pure returns (string memory) {
    uint256 code = toCode(err);
    bytes memory buf = abi.encodePacked("Code: ", code.toString(), ", Context: ", err.context);
    return string(buf);
  }

  function expect(
    bool cond,
    uint8 domain,
    uint8 detail,
    string memory context
  ) internal pure {
    Error memory err = fail(domain, ERR_TYPE_UNEXPECTED, detail, context);
    require(cond, toString(err));
  }

  function expect(
    bool cond,
    uint8 detail,
    string memory context
  ) internal pure {
    uint8 domain = errorDomain();
    expect(cond, domain, detail, context);
  }

  function check(
    bool cond,
    uint8 domain,
    uint8 etype,
    uint8 detail,
    string memory context
  ) internal pure {
    Error memory err = fail(domain, etype, detail, context);
    require(cond, toString(err));
  }

  function check(
    bool cond,
    uint8 etype,
    uint8 detail,
    string memory context
  ) internal pure {
    uint8 domain = errorDomain();
    check(cond, domain, etype, detail, context);
  }

  function checkParams(
    bool cond,
    uint8 detail,
    string memory context
  ) internal pure {
    uint8 domain = errorDomain();
    check(cond, domain, ERR_TYPE_PARAMETER, detail, context);
  }

  function checkBusiness(
    bool cond,
    uint8 detail,
    string memory context
  ) internal pure {
    uint8 domain = errorDomain();
    check(cond, domain, ERR_TYPE_BUSINESS, detail, context);
  }

  function checkMath(
    bool cond,
    uint8 detail,
    string memory context
  ) internal pure {
    uint8 domain = errorDomain();
    check(cond, domain, ERR_TYPE_MATH, detail, context);
  }

  function check(Error memory err) internal pure {
    requireNoError(err);
  }

  function requireNoError(Error memory err) internal pure {
    if (err.domain != 0) {
      revert(toString(err));
    }
  }
}
