pragma solidity =0.6.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../../src/libraries/Exponential.sol";

contract ExponentialSpec is Exponential {
  function testMulScalarTruncate() public {
    MathError err;
    uint256 result;
    (err, result) = mulScalarTruncate(Exp({ mantissa: 0.01e18 }), 500);
    Assert.equal(uint256(err), 0, "");
    Assert.equal(result, 5, "");

    Exp memory exp;
    (err, exp) = getExp(1, 1000);
    Assert.equal(uint256(err), 0, "");

    (err, result) = mulScalarTruncate(exp, 500);
    Assert.equal(uint256(err), 0, "");
    Assert.equal(result, 0, "");
  }
}
