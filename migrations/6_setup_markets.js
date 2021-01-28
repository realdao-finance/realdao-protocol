const RDOL = artifacts.require('RDOL')
const RWHT = artifacts.require('RWHT')
const RHBTC = artifacts.require('RHBTC')
const RHETH = artifacts.require('RHETH')
const REther = artifacts.require('REther')
const RTokenPart1 = artifacts.require('RTokenPart1')
const RTokenPart2 = artifacts.require('RTokenPart2')
const RTokenPart3 = artifacts.require('RTokenPart3')
const FakeHBTC = artifacts.require('FakeHBTC')
const FakeHETH = artifacts.require('FakeHETH')
const FakeWHT = artifacts.require('FakeWHT')
const DOL = artifacts.require('DOL')
// const Supreme = artifacts.require('Supreme')
const Orchestrator = artifacts.require('Orchestrator')
const MarketController = artifacts.require('MarketController')
const Addresses = require('./addresses.json')

let isLive
let rtokenParts
let orchestratorAddress
let admin
let controllerInstance

async function deployContracts(deployer) {
  await deployer.deploy(RTokenPart1)
  await deployer.deploy(RTokenPart2)
  await deployer.deploy(RTokenPart3)
  await deployer.deploy(RDOL)
  await deployer.deploy(RWHT)
  await deployer.deploy(RHBTC)
  await deployer.deploy(RHETH)

  if (!isLive) {
    await deployer.deploy(FakeHBTC)
    await deployer.deploy(FakeHETH)
    await deployer.deploy(FakeWHT)
  }
}

async function setupMarket(MarketContract, FakeTokenContract, underlyingSymbol, network) {
  const marketInstance = await MarketContract.deployed()
  const underlyingAddress = isLive ? Addresses[network][underlyingSymbol] : FakeTokenContract.address
  await marketInstance.initialize(orchestratorAddress, underlyingAddress, rtokenParts, { from: admin })
  await controllerInstance.supportMarket(MarketContract.address)
}

async function main(deployer, network, accounts) {
  isLive = network === 'mainnet'
  await deployContracts(deployer)

  if (network === 'unittest' || network === 'dev') {
    await deployer.deploy(REther)
  }

  if (network === 'unittest') return

  admin = accounts[0]
  rtokenParts = [RTokenPart1.address, RTokenPart2.address, RTokenPart3.address]

  // const supremeInstance = await Supreme.deployed()
  // orchestratorAddress = await supremeInstance.orchestrator()

  // const orchestratorInstance = await Orchestrator.at(orchestratorAddress)
  orchestratorAddress = Orchestrator.address
  const orchestratorInstance = await Orchestrator.deployed()
  const controllerAddress = await orchestratorInstance.getAddress('MARKET_CONTROLLER')
  controllerInstance = await MarketController.at(controllerAddress)

  const dolInstance = await DOL.deployed()
  await dolInstance.setSuperior(RDOL.address, { from: admin })

  const rdolInstance = await RDOL.deployed()
  await rdolInstance.initialize(orchestratorAddress, DOL.address, rtokenParts, { from: admin })
  await controllerInstance.supportMarket(RDOL.address)

  await Promise.all([
    setupMarket(RHBTC, FakeHBTC, 'HBTC', network),
    setupMarket(RHETH, FakeHETH, 'HETH', network),
    setupMarket(RWHT, FakeWHT, 'WHT', network),
  ])

  if (network === 'dev') {
    const retherInstance = await REther.deployed()
    await retherInstance.initialize(orchestratorAddress, rtokenParts)
    await controllerInstance.supportMarket(REther.address)
  }
}

module.exports = main
