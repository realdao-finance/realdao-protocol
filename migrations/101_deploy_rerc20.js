const RErc20 = artifacts.require('RErc20')

module.exports = function (deployer) {
  deployer.then(async () => {
    await deployer.deploy(RErc20)
  })
}
