const FakeLP_HT_DOL = artifacts.require('FakeLP_HT_DOL')
const FakeLP_HT_RDS = artifacts.require('FakeLP_HT_RDS')
const FakeLP_HUSD_DOL = artifacts.require('FakeLP_HUSD_DOL')
const FakeLP_HUSD_RDS = artifacts.require('FakeLP_HUSD_RDS')
const Distributor = artifacts.require('Distributor')
// const Supreme = artifacts.require('Supreme')
const Orchestrator = artifacts.require('Orchestrator')

async function main(deployer, network, accounts) {
  if (network === 'unittest') return

  const admin = accounts[0]

  if (network !== 'mainnet') {
    await deployer.deploy(FakeLP_HUSD_DOL)
    await deployer.deploy(FakeLP_HUSD_RDS)
    await deployer.deploy(FakeLP_HT_DOL)
    await deployer.deploy(FakeLP_HT_RDS)

    // const supremeInstance = await Supreme.deployed()
    // const orchestratorAddress = await supremeInstance.orchestrator()
    // const orchestratorInstance = await Orchestrator.at(orchestratorAddress)
    const orchestratorInstance = await Orchestrator.deployed()
    const distributorAddress = await orchestratorInstance.getAddress('DISTRIBUTOR')
    const distributorInstance = await Distributor.at(distributorAddress)

    await distributorInstance.createExchangingPool(FakeLP_HT_DOL.address, 100, 1, { from: admin })
    await distributorInstance.createExchangingPool(FakeLP_HT_RDS.address, 100, 1, { from: admin })
    await distributorInstance.createExchangingPool(FakeLP_HUSD_DOL.address, 100, 1, { from: admin })
    await distributorInstance.createExchangingPool(FakeLP_HUSD_RDS.address, 100, 1, { from: admin })
  }
}

module.exports = main
