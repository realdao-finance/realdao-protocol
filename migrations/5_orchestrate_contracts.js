const InterestRateModel = artifacts.require('InterestRateModel')
const FeedPriceOracle = artifacts.require('FeedPriceOracle')
const ProtocolReporter = artifacts.require('ProtocolReporter')
const RDS = artifacts.require('RDS')
const DOL = artifacts.require('DOL')
const Distributor = artifacts.require('Distributor')
const MarketController = artifacts.require('MarketController')
const MarketControllerLibrary = artifacts.require('MarketControllerLibrary')
const Council = artifacts.require('Council')
const Orchestrator = artifacts.require('Orchestrator')
// const Supreme = artifacts.require('Supreme')

function unuse() {}

async function main(deployer, network, accounts) {
  unuse(deployer)
  unuse(network)
  const admin = accounts[0]

  // const supremeInstance = await Supreme.deployed()
  // await supremeInstance.initialize(Orchestrator.address, { from: admin })

  const orchestratorParams = [
    MarketControllerLibrary.address,
    MarketController.address,
    Distributor.address,
    InterestRateModel.address,
    FeedPriceOracle.address,
    RDS.address,
    DOL.address,
    Council.address,
    ProtocolReporter.address,
  ]
  console.log('orchestratorParams', orchestratorParams)
  // const orchestratorProxyAddress = await supremeInstance.orchestrator()
  // const orchestratorProxy = await Orchestrator.at(orchestratorProxyAddress)
  // await orchestratorProxy.initialize(orchestratorParams, { from: admin })

  const orchestratorInstance = await Orchestrator.deployed()
  await orchestratorInstance.initialize(orchestratorParams, { from: admin })

  const rdsInstance = await RDS.deployed()
  const distributorAddress = await orchestratorInstance.getAddress('DISTRIBUTOR')
  await rdsInstance.setSuperior(distributorAddress)
}

module.exports = main
