const MockController = artifacts.require('MockController')
const MockPriceOracle = artifacts.require('MockPriceOracle')
const MockOrchestrator = artifacts.require('MockOrchestrator')
const MockMarketControllerV2 = artifacts.require('MockMarketControllerV2')
const MockERC20 = artifacts.require('MockERC20')

async function main(deployer, network) {
  if (network === 'unittest') {
    await deployer.deploy(MockController)
    await deployer.deploy(MockPriceOracle)
    await deployer.deploy(MockOrchestrator)
    await deployer.deploy(MockMarketControllerV2)
    await deployer.deploy(MockERC20)
  }
}

module.exports = main
