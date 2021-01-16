const { expectRevert, expectSuccess } = require('../util/expect')
const { advanceBlocks } = require('../util/advance')
const RDS = artifacts.require('RDS')
const Distributor = artifacts.require('Distributor')
const MockPriceOracle = artifacts.require('MockPriceOracle')
const InterestRateModel = artifacts.require('InterestRateModel')
const MarketControllerLibrary = artifacts.require('MarketControllerLibrary')
const MarketController = artifacts.require('MarketController')
const RTokenPart1 = artifacts.require('RTokenPart1')
const RTokenPart2 = artifacts.require('RTokenPart2')
const RTokenPart3 = artifacts.require('RTokenPart3')
const REther = artifacts.require('REther')
const RDOL = artifacts.require('RDOL')
const DOL = artifacts.require('DOL')
const ProtocolReporter = artifacts.require('ProtocolReporter')
const MockOrchestrator = artifacts.require('MockOrchestrator')

const MAX_UINT256 = '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
const ETH_PRICE = 400e8
const ETH_PRICE2 = 250e8
const DOL_FIRST_SUPPLY = 1e16

const POOL_STATE_ACTIVE = 1
const POOL_STATE_CLOSED = 2

const MARKET_STATE_LISTED = 1
const MARKET_STATE_CLOSING = 2
const MARKET_STATE_LIQUIDATING = 3

let admin
let accounts
let interestRate
let oracle
let distributor
let rds
let dol
let controllerLib
let controller
let rTokenParts
let rETH
let rDOL
let reporter
let orchestrator

async function deployContracts() {
  accounts = await web3.eth.getAccounts()
  admin = accounts[0]

  interestRate = await InterestRateModel.deployed()
  oracle = await MockPriceOracle.deployed()
  distributor = await Distributor.deployed()
  rds = await RDS.deployed()
  dol = await DOL.deployed()

  const ControllerLibrary = await MarketControllerLibrary.deployed()
  controllerLib = ControllerLibrary.address
  controller = await MarketController.deployed()

  const rTokenPart1 = await RTokenPart1.deployed()
  const rTokenPart2 = await RTokenPart2.deployed()
  const rTokenPart3 = await RTokenPart3.deployed()
  rTokenParts = [rTokenPart1.address, rTokenPart2.address, rTokenPart3.address]
  rETH = await REther.deployed()
  rDOL = await RDOL.deployed()

  reporter = await ProtocolReporter.deployed()
  orchestrator = await MockOrchestrator.deployed()
}

async function initializeContracts() {
  await deployContracts()

  await orchestrator.setMarketController(controller.address)
  await orchestrator.setRDS(rds.address)
  await orchestrator.setInterestRateModel(interestRate.address)
  await orchestrator.setOracle(oracle.address)
  await orchestrator.setDistributor(distributor.address)

  await interestRate.initialize(orchestrator.address)
  await oracle.initialize(orchestrator.address)
  await rds.initialize(distributor.address)
  await distributor.initialize(orchestrator.address)
  await controller.initialize(orchestrator.address)
  await controller.bind(controllerLib)
  await reporter.initialize(orchestrator.address)

  await rETH.initialize(orchestrator.address, rTokenParts)
  await rDOL.initialize(orchestrator.address, dol.address, rTokenParts)
}

async function setupContracts() {
  await initializeContracts()

  // system setup after initialization
  await controller.supportMarket(rETH.address)
  await controller.supportMarket(rDOL.address)

  const currentBlock = await web3.eth.getBlock('latest')
  await distributor.createLendingPool(rETH.address, currentBlock.number + 2, { from: admin })
  await distributor.createLendingPool(rDOL.address, currentBlock.number + 3, { from: admin })
  await advanceBlocks(2)
  await distributor.openPool(0, { from: admin })
  await distributor.openPool(1, { from: admin })
}

contract('RToken:mint', () => {
  const mintAmount = 1.2e18
  let user

  before('initialize contracts', async () => {
    await initializeContracts()
    user = accounts[1]

    const E28 = '10000000000000000000000000000'
    const E18 = '1000000000000000000'
    assert.equal((await rETH.initialExchangeRateMantissa()).toString(), E28)
    assert.equal((await rDOL.initialExchangeRateMantissa()).toString(), E18)
    assert.equal((await rDOL.getCash()).toString(), DOL_FIRST_SUPPLY.toString())
  })

  it('should fail to mint ether because market is not listed', async () => {
    await expectRevert(rETH.mint({ value: mintAmount, from: user }))
  })

  it('should success to mint ether', async () => {
    await controller.supportMarket(rETH.address, { from: admin })
    const currentBlock = await web3.eth.getBlock('latest')
    await distributor.createLendingPool(rETH.address, currentBlock.number + 2, { from: admin })
    await advanceBlocks(3)
    await distributor.openPool(0, { from: admin })
    await rETH.mint({ value: mintAmount, from: user })
    assert.equal((await rETH.balanceOf(user)).toString(), (mintAmount / 1e10).toString())
    assert.equal((await rETH.balanceOfUnderlying(user)).toString(), mintAmount.toString())

    const record = await distributor.getAccountRecord(user, 0)
    assert.equal(record.power.toString(), mintAmount.toString())
  })
})

contract('RToken:borrow', () => {
  const mintAmount = 1.2e18
  const borrowAmount = 100e8
  let user

  before('initialize contracts', async () => {
    await initializeContracts()
    user = accounts[1]

    await controller.supportMarket(rETH.address)
    await controller.supportMarket(rDOL.address)

    const currentBlock = await web3.eth.getBlock('latest')
    await distributor.createLendingPool(rETH.address, currentBlock.number + 2, { from: admin })
    await distributor.createLendingPool(rDOL.address, currentBlock.number + 3, { from: admin })
    await advanceBlocks(2)
  })

  it('should fail to borrow without supply', async () => {
    await expectRevert(rDOL.borrow(borrowAmount, { from: user }))
  })

  it('should success to borrow', async () => {
    await rETH.mint({ value: mintAmount, from: user })
    await expectSuccess(rDOL.borrow(borrowAmount, { from: user }))
  })
})

contract('RToken:repayBorrow', () => {
  const mintAmount = 1.2e18
  const borrowAmount = 100e8
  let user

  before('setup contracts', async () => {
    await setupContracts()
    user = accounts[1]

    await rETH.mint({ value: mintAmount, from: user })
    await expectSuccess(rDOL.borrow(borrowAmount, { from: user }))
  })

  it('should fail to repayBorrow if rToken have no allowance', async () => {
    await expectRevert(rDOL.repayBorrow(borrowAmount / 2, { from: user }))
  })

  it('should success to repayBorrow a part', async () => {
    await dol.approve(rDOL.address, borrowAmount, { from: user })
    assert.equal((await rDOL.borrowBalanceCurrent(user)).toString(), borrowAmount.toString())

    await expectSuccess(rDOL.repayBorrow(borrowAmount / 2, { from: user }))
    assert.equal((await rDOL.borrowBalanceCurrent(user)).toString(), (borrowAmount / 2).toString())

    const record = await distributor.getAccountRecord(user, 1)
    assert.equal(record.power.toString(), (borrowAmount / 2).toString())
  })

  it('should success to repayBorrow all left', async () => {
    await expectSuccess(rDOL.repayBorrowBehalf(user, MAX_UINT256, { from: user }))
    assert.equal((await rDOL.borrowBalanceCurrent(user)).toString(), '0')

    const record = await distributor.getAccountRecord(user, 1)
    assert.equal(record.power.toString(), '0')
  })
})

contract('RToken:redeem', () => {
  const mintAmount = 1e18
  const borrowAmount = 200e8
  let user

  before('setup contracts', async () => {
    await setupContracts()
    user = accounts[1]

    await rETH.mint({ value: mintAmount, from: user })
  })

  it('should fail to redeem above the quote', async () => {
    await expectRevert(rETH.redeem((mintAmount / 1e10) * 2, { from: user }))
  })

  it('should fail to redeem if the account have no enough liquidity', async () => {
    await expectSuccess(rDOL.borrow(borrowAmount, { from: user }))

    let currentBalance = (await rETH.balanceOf(user)).toString()
    await expectRevert(rETH.redeem(currentBalance, { from: user }))
  })

  it('should success to redeem', async () => {
    await dol.approve(rDOL.address, borrowAmount, { from: user })

    await expectSuccess(rDOL.repayBorrow(borrowAmount, { from: user }))

    let currentBalance = (await rETH.balanceOf(user)).toString()
    assert.equal(currentBalance, (mintAmount / 1e10).toString())

    await expectSuccess(rETH.redeem(currentBalance, { from: user }))
    assert.equal((await rETH.balanceOf(user)).toString(), '0')

    const record = await distributor.getAccountRecord(user, 1)
    assert.equal(record.power.toString(), '0')
  })
})

contract('RToken:liquidateBorrow', () => {
  const mintAmount1 = 1e18
  const mintAmount2 = 5e18
  const borrowAmount = 200e8
  let user1
  let user2

  before('setup contracts', async () => {
    await setupContracts()
    user1 = accounts[1]
    user2 = accounts[2]

    await rETH.mint({ value: mintAmount1, from: user1 })
    await rETH.mint({ value: mintAmount2, from: user2 })
    await expectSuccess(rDOL.borrow(borrowAmount, { from: user1 }))
    await expectSuccess(rDOL.borrow(borrowAmount, { from: user2 }))
  })

  it('should fail to liquidateBorrow because insufficient shortfall', async () => {
    await expectRevert(rDOL.liquidateBorrow(user1, borrowAmount, rETH.address, { from: user2 }))
  })

  it('should fail to liquidateBorrow if repay amount exceeds the max close amount', async () => {
    let liquidity = await controller.getAccountLiquidity(user1)
    assert.equal(liquidity[1].toNumber(), 0)

    await oracle.setUnderlyingPrice('ETH', ETH_PRICE2.toString())
    liquidity = await controller.getAccountLiquidity(user1)
    assert.equal(liquidity[1].toNumber(), 1250000000)

    await expectRevert(rDOL.liquidateBorrow(user1, borrowAmount, rETH.address, { from: user2 }))
  })

  it('should success to liquidateBorrow', async () => {
    await dol.approve(rDOL.address, borrowAmount / 2, { from: user2 })
    await expectSuccess(rDOL.liquidateBorrow(user1, borrowAmount / 2, rETH.address, { from: user2 }))
    const liquidity = await controller.getAccountLiquidity(user1)
    assert.equal(liquidity[0].toNumber(), 650000000)
    assert.equal(liquidity[1].toNumber(), 0)
  })
})

contract('RToken:removeMarket', () => {
  before('setup contracts', async () => {
    await setupContracts()

    await rETH.mint({ value: 1e18, from: accounts[1] })
    await rDOL.borrow(200e8, { from: accounts[1] })
  })

  it('should fail to set market to liquidating state from listed state', async () => {
    await expectRevert(controller.liquidateMarket(rDOL.address))
  })

  it('should fail to set market to remove a listed market directly', async () => {
    await expectRevert(controller.removeMarket(rDOL.address))
  })

  it('should fail to close a unlisted market', async () => {
    await expectRevert(controller.closeMarket(controller.address))
  })

  it('should success to close a listed market', async () => {
    let pools = await distributor.getAllPools()
    assert.equal(pools.length, 2)
    assert.equal(pools[0].state, POOL_STATE_ACTIVE)
    assert.equal(pools[1].state, POOL_STATE_ACTIVE)

    let market = await controller.getMarket(rDOL.address)
    assert.equal(market[0], MARKET_STATE_LISTED)

    await expectSuccess(controller.closeMarket(rDOL.address))

    pools = await distributor.getAllPools()
    assert.equal(pools.length, 2)
    assert.equal(pools[0].state, POOL_STATE_ACTIVE)
    assert.equal(pools[1].state, POOL_STATE_CLOSED)

    market = await controller.getMarket(rDOL.address)
    assert.equal(market[0], MARKET_STATE_CLOSING)
  })

  it('should fail to remove a market in closing state', async () => {
    await expectRevert(controller.removeMarket(rDOL.address))
  })

  it('should success to liquidate a closing market', async () => {
    await expectSuccess(controller.liquidateMarket(rDOL.address))
    let market = await controller.getMarket(rDOL.address)
    assert.equal(market[0].toString(), MARKET_STATE_LIQUIDATING)
  })

  it('should success to remove a liquidating market', async () => {
    await expectSuccess(controller.removeMarket(rDOL.address))
    let market = await controller.getMarket(rDOL.address)
    assert.equal(market[0], 0)
  })
})

contract('RToken:liquidateMarket', () => {
  const mintAmount1 = 1e18
  const mintAmount2 = 5e18
  const borrowAmount1 = 200e8
  const borrowAmount2 = 1000e8
  let user1
  let user2

  before('setup contracts', async () => {
    await setupContracts()
    user1 = accounts[1]
    user2 = accounts[2]

    await rETH.mint({ value: mintAmount1, from: user1 })
    await rETH.mint({ value: mintAmount2, from: user2 })
    await rDOL.borrow(borrowAmount1, { from: user1 })
    await rDOL.borrow(borrowAmount2, { from: user2 })
  })

  it('should fail to mint/borrow after close market', async () => {
    await dol.approve(rDOL.address, 10e8, { from: user1 })
    await rDOL.mint(10e8, { from: user1 })
    await controller.closeMarket(rDOL.address)
    await expectRevert(rDOL.mint(10e8, { from: user1 }))
    await expectRevert(rDOL.borrow(10e8, { from: user1 }))
  })

  it('should success to transfer/repay/redeem in closing market', async () => {
    await rDOL.transfer(user2, 1e8, { from: user1 })
    await rDOL.redeem(1e8, { from: user1 })
    await rETH.redeem(0.1e8, { from: user1 })

    let borrowBalance = await rDOL.borrowBalanceCurrent(user1)
    assert.equal(borrowBalance.toNumber(), borrowAmount1)
    await dol.approve(rDOL.address, 20e8, { from: user1 })
    await rDOL.repayBorrow(20e8, { from: user1 })
    borrowBalance = await rDOL.borrowBalanceCurrent(user1)
    assert.equal(borrowBalance.toNumber(), 180e8)
  })

  it('should fail to liquidateBorrow if no shortfall', async () => {
    const liquidity = await controller.getAccountLiquidity(user1)
    assert.equal(liquidity[1].toNumber(), 0)
    await expectRevert(rDOL.liquidateBorrow(user1, 10e8, rETH.address, { from: user2 }))
  })

  it('should success to liquidateBorrow if market is in liquidating state', async () => {
    await controller.liquidateMarket(rDOL.address)
    let borrowBalance = await rDOL.borrowBalanceCurrent(user1)
    assert.equal(borrowBalance.toNumber(), 180e8)

    await dol.approve(rDOL.address, 180e8, { from: user2 })
    await expectSuccess(rDOL.liquidateBorrow(user1, 180e8, rETH.address, { from: user2 }))
    borrowBalance = await rDOL.borrowBalanceCurrent(user1)
    assert.equal(borrowBalance.toNumber(), 0)
  })
})
