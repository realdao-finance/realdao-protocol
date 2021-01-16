const InterestRateModel = artifacts.require('InterestRateModel')
// const ChainlinkPriceOracle = artifacts.require('ChainlinkPriceOracle')
const FeedPriceOracle = artifacts.require('FeedPriceOracle')
const ProtocolReporter = artifacts.require('ProtocolReporter')
const RDS = artifacts.require('RDS')
const DOL = artifacts.require('DOL')
const Distributor = artifacts.require('Distributor')
const MarketController = artifacts.require('MarketController')
const MarketControllerLibrary = artifacts.require('MarketControllerLibrary')

async function main(deployer) {
  await deployer.deploy(InterestRateModel)
  await deployer.deploy(FeedPriceOracle)
  await deployer.deploy(RDS)
  await deployer.deploy(DOL)
  await deployer.deploy(ProtocolReporter)
  await deployer.deploy(Distributor)
  await deployer.deploy(MarketControllerLibrary)
  await deployer.deploy(MarketController)
}

module.exports = main
