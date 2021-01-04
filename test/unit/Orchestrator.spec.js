const network = process.argv[4]
const { expectSuccess, expectRevert } = require('../util/expect')
const { advanceBlocks } = require('../util/advance')
const MockPriceOracle = artifacts.require('MockPriceOracle')
const InterestRateModel = artifacts.require('InterestRateModel')
const MarketControllerPart1 = artifacts.require('MarketControllerPart1')
const MarketController = artifacts.require('MarketController')
const Distributor = artifacts.require('Distributor')
const Council = artifacts.require('Council')
const ProtocolReporter = artifacts.require('ProtocolReporter')
const DOL = artifacts.require('DOL')
const RDS = artifacts.require('RDS')
const RTokenPart1 = artifacts.require('RTokenPart1')
const RTokenPart2 = artifacts.require('RTokenPart2')
const RTokenPart3 = artifacts.require('RTokenPart3')
const REther = artifacts.require('REther')
const RDOL = artifacts.require('RDOL')
const Orchestrator = artifacts.require('Orchestrator')
const UpgradableProxy = artifacts.require('UpgradableProxy')
const MockMarketControllerV2 = artifacts.require('MockMarketControllerV2')

const MAX_UINT256 = '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
const ETH_PRICE = 400e8
const ETH_PRICE2 = 250e8
const DOL_FIRST_SUPPLY = 1e16

let oracle
let interestRate
let controller
let distributor
let council
let reporter
let dol
let rds
let rETH
let rDOL
let orchestrator

let accounts
let admin

async function initializeContracts() {
  accounts = await web3.eth.getAccounts()
  admin = accounts[0]

  const oracleImpl = await MockPriceOracle.deployed()
  const interestRateImpl = await InterestRateModel.deployed()

  await MarketControllerPart1.deployed()
  const controllerImpl = await MarketController.deployed()
  const distributorImpl = await Distributor.deployed()
  const councilImpl = await Council.deployed()

  dol = await DOL.deployed()
  rds = await RDS.deployed()

  await RTokenPart1.deployed()
  await RTokenPart2.deployed()
  await RTokenPart3.deployed()

  rETH = await REther.deployed()
  rDOL = await RDOL.deployed()
  reporter = await ProtocolReporter.deployed()
  orchestrator = await Orchestrator.deployed()
  await MockMarketControllerV2.deployed()

  await orchestrator.initialize(
    [MarketControllerPart1.address],
    [
      controllerImpl.address,
      distributorImpl.address,
      councilImpl.address,
      interestRateImpl.address,
      oracleImpl.address,
      dol.address,
      rds.address,
      reporter.address,
    ],
    [RTokenPart1.address, RTokenPart2.address, RTokenPart3.address],
    rETH.address,
    rDOL.address,
    {
      from: admin,
    }
  )

  oracle = new MockPriceOracle(await orchestrator.getOracle())
  interestRate = new InterestRateModel(await orchestrator.getInterestRateModel())
  controller = new MarketController(await orchestrator.getMarketController())
  distributor = new Distributor(await orchestrator.getDistributor())
  council = new Council(await orchestrator.getCouncil())
}

async function setupContracts() {
  await initializeContracts()

  // system setup after initialization
  const currentBlock = await web3.eth.getBlock('latest')

  await distributor.createLendingPool(rETH.address, currentBlock.number + 2, { from: admin })
  await distributor.createLendingPool(rDOL.address, currentBlock.number + 3, { from: admin })
  await advanceBlocks(2)

  // setup mock data
  await oracle.setUnderlyingPrice('ETH', ETH_PRICE.toString())
}

contract('Orchestrator:smoke', () => {
  let user1
  let user2
  let user3

  before('setup contracts', async () => {
    await setupContracts()
    user1 = accounts[1]
    user2 = accounts[2]
    user3 = accounts[3]
  })

  it('supply ether', async () => {
    await rETH.mint({ value: 10e18, from: user1 })
    await rETH.mint({ value: 2e18, from: user2 })
  })

  it('borrow dol', async () => {
    await expectSuccess(rDOL.borrow(2000e8, { from: user1 }))
    await expectSuccess(rDOL.borrow(400e8, { from: user2 }))
  })

  it('transfer dol', async () => {
    await dol.transfer(user3, 1000e8, { from: user1 })
  })

  it('supply dol', async () => {
    await dol.approve(rDOL.address, 500e8, { from: user3 })
    await rDOL.mint(500e8, { from: user3 })
  })

  it('borrow ether', async () => {
    await expectSuccess(rETH.borrow(String(0.5e18), { from: user3 }))
  })

  it('transfer rETH', async () => {
    await rETH.transfer(user3, 1e8, { from: user1 })
  })

  it('transfer rDOL', async () => {
    await dol.transfer(user3, 100e8, { from: user2 })
  })

  it('redeem ether', async () => {
    await rETH.redeem(0.5e8, { from: user3 })
  })

  it('redeem dol', async () => {
    await rDOL.redeem(50e8, { from: user3 })
  })

  it('markets', async () => {
    const markets = await reporter.getAllMarketInfo()
    assert.equal(markets.length, 2)
  })

  it('pools', async () => {
    await distributor.getAccountRecords(user1)
    await distributor.getAccountRecords(user2)
    await distributor.getAccountRecords(user3)
    await distributor.getDistributorStats()
    await distributor.getAllPools()
  })

  it('account', async () => {
    await controller.getAccountLiquidity(user1)
    await controller.getAccountLiquidity(user2)
    await controller.getAccountLiquidity(user3)
    await reporter.getAllRTokenBalances(user1)
    await reporter.getAllRTokenBalances(user2)
    await reporter.getAllRTokenBalances(user3)
  })

  it('prices', async () => {
    await reporter.getUnderlyingPrices()
  })
})

contract('Orchestrator:initialize', () => {
  before('setup contracts', async () => {
    await initializeContracts()
  })

  it('check orchestrator states after initialization', async () => {
    assert.equal(await orchestrator.guardian(), admin)
    assert.equal(await orchestrator.getRDS(), rds.address)
    assert.equal(await orchestrator.getDOL(), dol.address)
    assert.equal(await orchestrator.getOracle(), oracle.address)
    assert.equal(await orchestrator.getInterestRateModel(), interestRate.address)
    assert.equal(await orchestrator.getReporter(), reporter.address)
    assert.equal(await orchestrator.getCouncil(), council.address)
    assert.equal(await orchestrator.getDistributor(), distributor.address)
    assert.equal(await orchestrator.getMarketController(), controller.address)
  })

  it('check proxy states', async () => {
    const controllerProxy = new UpgradableProxy(controller.address)
    assert.equal(await controllerProxy._implementation(), MarketController.address)
    assert.equal(await controllerProxy._admin(), orchestrator.address)
  })

  it('check proxy events', async () => {
    const proxyCreatedEvents = await orchestrator.getPastEvents('ProxyCreated')
    assert.equal(proxyCreatedEvents.length, 2)
    expect(proxyCreatedEvents[0].args).to.include({
      key: 'MARKET_CONTROLLER',
      proxy: controller.address,
      impl: MarketController.address,
    })

    const contractChangedEvents = await orchestrator.getPastEvents('ContractChanged')
    assert.equal(contractChangedEvents.length, 6)
    expect(contractChangedEvents[0].args).to.include({
      key: 'COUNCIL',
      oldAddr: '0x0000000000000000000000000000000000000000',
      newAddr: council.address,
    })
    expect(contractChangedEvents[5].args).to.include({
      key: 'REPORTER',
      oldAddr: '0x0000000000000000000000000000000000000000',
      newAddr: reporter.address,
    })

    const proxyUpgradedEvents = await orchestrator.getPastEvents('ProxyUpgraded')
    assert.equal(proxyUpgradedEvents.length, 0)
  })
})

contract('Orchestrator:upgrade', () => {
  let allMarkets

  before('setup contracts', async () => {
    await setupContracts()

    allMarkets = await controller.getAllMarkets()
    assert.equal(allMarkets.length, 2)
  })

  it('check proxy state after upgrade', async () => {
    await orchestrator.upgradeMarketController(MockMarketControllerV2.address)
    assert.equal(await orchestrator.getMarketController(), controller.address)

    const controllerProxy = new UpgradableProxy(controller.address)
    assert.equal(await controllerProxy._implementation(), MockMarketControllerV2.address)

    const events = await orchestrator.getPastEvents('ProxyUpgraded')
    assert.equal(events.length, 1)
    expect(events[0].args).to.include({
      key: 'MARKET_CONTROLLER',
      proxy: controller.address,
      oldImpl: MarketController.address,
      newImpl: MockMarketControllerV2.address,
    })
  })

  it('shoud not affect old state after upgrade', async () => {
    const markets = await controller.getAllMarkets()
    expect(markets).to.deep.equal(allMarkets)
  })

  it('shoud not affect old state after writing new state', async () => {
    const newController = new MockMarketControllerV2(controller.address)
    await newController.write(1, 100)
    assert.equal((await newController.read(1)).toString(), '100')

    const markets = await controller.getAllMarkets()
    expect(markets).to.deep.equal(allMarkets)
  })

  it('should fail to upgrade distributor after set it final', async () => {
    await orchestrator.setDistributorFinal()
    await expectRevert(orchestrator.upgradeDistributor(MockMarketControllerV2.address))
  })
})
