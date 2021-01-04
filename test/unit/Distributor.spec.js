const { advanceBlocks } = require('../util/advance')
const { expectRevert } = require('../util/expect')
const RDS = artifacts.require('RDS')
const MockErc20 = artifacts.require('MockErc20')
const MockController = artifacts.require('MockController')
const MockOrchestrator = artifacts.require('MockOrchestrator')
const Distributor = artifacts.require('Distributor')

const BLOCKS_PER_YEAR = 2102400
const REWARDS_PER_BLOCK = 400000000
const MANTISSA = 1e18
const POOL_TYPE_LENDING = 1
const POOL_TYPE_EXCHANGING = 2
const POOL_STATE_NOT_START = 0
const POOL_STATE_ACTIVE = 1
const POOL_STATE_CLOSED = 2

let accounts
let admin
let controller
let rds
let distributor
let orchestrator

async function deployContracts() {
  accounts = await web3.eth.getAccounts()
  admin = accounts[0]

  rds = await RDS.deployed()
  controller = await MockController.deployed()
  distributor = await Distributor.deployed()
  orchestrator = await MockOrchestrator.deployed()
}

async function initializeContracts() {
  await deployContracts()

  await orchestrator.setMarketController(controller.address)
  await orchestrator.setDistributor(distributor.address)
  await orchestrator.setRDS(rds.address)
  await orchestrator.setCouncil(admin)

  await rds.initialize(distributor.address)
  await distributor.initialize(orchestrator.address)
  await controller.initialize(orchestrator.address)
}

contract('Distributor:initialize', () => {
  before('initialize Distributor', initializeContracts)

  it('should be ok validating initial variables', async () => {
    assert.equal(await distributor.rewardsPerBlock(), 0)
    assert.equal(await distributor.mineStartBlock(), 0)
    assert.equal(await distributor.nextHalvingBlock(), 0)
  })

  it('should fail to update lending power by unlisted token contract', async () => {
    const someUser = accounts[1]
    const market = accounts[2]
    await expectRevert(distributor.updateLendingPower(someUser, 1000, { from: market }))
  })

  it('should fail to create lending pool by normal user which are not admin', async () => {
    const someUser = accounts[1]
    const someToken = accounts[2]
    await expectRevert(distributor.createLendingPool(someToken, 10000, { from: someUser }))
  })
})

contract('Distributor:createLendingPool', () => {
  let someToken
  let currentBlock

  before('initialize Distributor', async () => {
    await initializeContracts()
    someToken = accounts[1]
    currentBlock = await web3.eth.getBlock('latest')
  })

  it('should fail to createLendingPool for unlisted market', async () => {
    await expectRevert(distributor.createLendingPool(someToken, 10000, { from: admin }))
  })

  it('should fail to createLendingPool with invalid startBlock', async () => {
    await controller.addMarket(someToken)
    await expectRevert(distributor.createLendingPool(someToken, currentBlock.number, { from: admin }))
  })

  it('should success to createLendingPool', async () => {
    const startBlockNumber = currentBlock.number + 5
    await distributor.createLendingPool(someToken, startBlockNumber, { from: admin })
    assert.equal(await distributor.activePools(), 0)
    const pool = await distributor.getPool(0)
    assert.equal(pool.id, 0)
    assert.equal(pool.ptype, POOL_TYPE_LENDING)
    assert.equal(pool.tokenAddr, someToken)
    assert.equal(pool.state, POOL_STATE_NOT_START)
    assert.equal(pool.startBlock, startBlockNumber)

    const allPools = await distributor.getAllPools()
    assert.equal(allPools.length, 1)
    assert.equal(allPools[0].id, 0)
  })

  it('should fail to createLendingPool for the same market', async () => {
    await expectRevert(distributor.createLendingPool(someToken, currentBlock.number + 5, { from: admin }))
  })
})

contract('Distributor:createExchangingPool', () => {
  let currentBlock
  let someToken

  before('initialize Distributor', async () => {
    await initializeContracts()
    currentBlock = await web3.eth.getBlock('latest')
    someToken = accounts[1]
  })

  it('should fail to createExchangingPool with invalid startBlock', async () => {
    await expectRevert(distributor.createExchangingPool(someToken, currentBlock.number), { from: admin })
  })

  it('should success to createExchangingPool', async () => {
    const startBlockNumber = currentBlock.number + 5
    await distributor.createExchangingPool(someToken, startBlockNumber, { from: admin })
    assert.equal(await distributor.activePools(), 0)
    const pool = await distributor.getPool(0)
    assert.equal(pool.id, 0)
    assert.equal(pool.ptype, POOL_TYPE_EXCHANGING)
    assert.equal(pool.tokenAddr, someToken)
    assert.equal(pool.state, POOL_STATE_NOT_START)
    assert.equal(pool.startBlock, startBlockNumber)
  })

  it('should fail to createExchangingPool for the same token', async () => {
    await expectRevert(distributor.createExchangingPool(someToken, currentBlock.number + 5, { from: admin }))
  })
})

contract('Distributor:openPool', () => {
  let currentBlock
  let startBlockNumber
  let market
  let id
  let someUser

  before('initialize Distributor', async () => {
    await initializeContracts()
    market = accounts[1]
    someUser = accounts[2]
    currentBlock = await web3.eth.getBlock('latest')
    startBlockNumber = currentBlock.number + 5

    await controller.addMarket(market)
    await distributor.createLendingPool(market, startBlockNumber, { from: admin })
    id = 0
  })

  it('should fail to openPool with invalid id', async () => {
    await expectRevert(distributor.openPool(100, { from: someUser }))
  })

  it('should fail to openPool before startBlock', async () => {
    await expectRevert(distributor.openPool(id, { from: someUser }))
  })

  it('should success to openPool', async () => {
    currentBlock = await advanceBlocks(5)
    await distributor.openPool(id, { from: someUser })
    assert.equal(await distributor.rewardsPerBlock(), REWARDS_PER_BLOCK)
    assert.equal(await distributor.activePools(), 1)
    assert.equal((await distributor.mineStartBlock()).toNumber(), currentBlock.number + 1)
    assert.equal((await distributor.nextHalvingBlock()).toNumber(), currentBlock.number + 1 + BLOCKS_PER_YEAR)

    const pool = await distributor.getPool(0)
    assert.equal(pool.id, 0)
    assert.equal(pool.ptype, POOL_TYPE_LENDING)
    assert.equal(pool.tokenAddr, market)
    assert.equal(pool.state, POOL_STATE_ACTIVE)
    assert.equal(pool.startBlock, startBlockNumber)
  })

  it('should fail to open an active pool', async () => {
    await expectRevert(distributor.openPool(id, { from: someUser }))
  })
})

contract('Distributor:closePool', () => {
  let market
  let id
  let someUser

  before('initialize Distributor', async () => {
    await initializeContracts()
    market = accounts[1]
    someUser = accounts[2]

    const currentBlock = await web3.eth.getBlock('latest')
    await controller.addMarket(market)
    await distributor.createLendingPool(market, currentBlock.number + 5, { from: admin })
    id = 0

    await advanceBlocks(5)
    await distributor.openPool(id, { from: someUser })
  })

  it('should fail to closePool with invalid token', async () => {
    await expectRevert(controller.closePool(someUser, { from: admin }))
  })

  it('should success to closePool', async () => {
    await controller.closePool(market, { from: admin })
    const pool = await distributor.getPool(0)
    assert.equal(pool.id, id)
    assert.equal(pool.state, POOL_STATE_CLOSED)
  })

  it('should fail to close an already closed pool', async () => {
    await expectRevert(controller.closePool(market, { from: admin }))
  })
})

contract('Distributor:updateLendingPower', () => {
  let market
  let id
  let someUser
  let currentBlock

  before('initialize Distributor', async () => {
    await initializeContracts()
    market = accounts[1]
    someUser = accounts[2]

    currentBlock = await web3.eth.getBlock('latest')
    await controller.addMarket(market)
    await distributor.createLendingPool(market, currentBlock.number + 5, { from: admin })
    id = 0
  })

  it('should fail to updateLendingPower by unlisted market', async () => {
    await expectRevert(distributor.updateLendingPower(someUser, 1000, { from: someUser }))
  })

  it('should fail to updateLendingPower before startBlock', async () => {
    await expectRevert(distributor.updateLendingPower(someUser, 1000, { from: market }))
  })

  it('should success to updateLendingPower', async () => {
    currentBlock = await advanceBlocks(5)

    const user1Power = 1000
    await distributor.updateLendingPower(someUser, user1Power, { from: market })

    const index1 = 0n
    let pool = await distributor.getPool(id)
    assert.equal(pool.id, id)
    assert.equal(pool.state, POOL_STATE_ACTIVE)
    assert.equal(pool.rewardIndex, index1.toString())
    assert.equal(pool.lastBlockNumber, currentBlock.number + 1)
    assert.equal(pool.accumulatedPower, user1Power)
    assert.equal(pool.accumulatedTokens, 0)
    assert.equal(pool.totalPower, 0)

    let record = await distributor.getAccountRecord(someUser, id)
    assert.equal(record.power, user1Power)
    assert.equal(record.mask, 0)
    assert.equal(record.settled, 0)
    assert.equal(record.claimed, 0)

    const user2 = accounts[3]
    const user2Power = 2000
    await distributor.updateLendingPower(user2, user2Power, { from: market })

    const index2 = index1 + (BigInt(REWARDS_PER_BLOCK) * BigInt(MANTISSA)) / BigInt(user1Power)
    const mask2 = index2 * BigInt(user2Power)
    pool = await distributor.getPool(id)
    assert.equal(pool.rewardIndex, index2.toString())
    assert.equal(pool.lastBlockNumber, currentBlock.number + 2)
    assert.equal(pool.accumulatedPower, user2Power)
    assert.equal(pool.accumulatedTokens, 0)
    assert.equal(pool.totalPower, user1Power)

    record = await distributor.getAccountRecord(user2, id)
    assert.equal(record.power, user2Power)
    assert.equal(record.mask, mask2.toString())
    assert.equal(record.settled, 0)
    assert.equal(record.claimed, 0)

    const user2NewPower = 1000
    await distributor.updateLendingPower(user2, user2NewPower, { from: market })

    const totalPower = user1Power + user2Power
    const index3 = index2 + (BigInt(REWARDS_PER_BLOCK) * BigInt(MANTISSA)) / BigInt(totalPower)
    const settled = (index3 * BigInt(user2Power) - mask2) / BigInt(MANTISSA)
    const mask3 = index3 * BigInt(user2NewPower)
    pool = await distributor.getPool(id)
    assert.equal(pool.rewardIndex, index3.toString())
    assert.equal(pool.lastBlockNumber, currentBlock.number + 3)
    assert.equal(pool.accumulatedPower, user2NewPower - user2Power)
    assert.equal(pool.accumulatedTokens, 0)
    assert.equal(pool.totalPower, totalPower)

    record = await distributor.getAccountRecord(user2, id)
    assert.equal(record.power, user2NewPower)
    assert.equal(record.mask, mask3.toString())
    assert.equal(record.settled, settled.toString())
    assert.equal(record.claimed, 0)
  })
})

contract('Distributor:mintExchangingPool', () => {
  let lpToken
  let id
  let user
  const balance = 1000e8
  let currentBlock

  before('initialize Distributor', async () => {
    await initializeContracts()
    user = accounts[1]

    lpToken = await MockErc20.deployed()
    await lpToken.transfer(user, balance, { from: admin })
    assert.equal(await lpToken.balanceOf(user), balance)

    currentBlock = await web3.eth.getBlock('latest')
    await distributor.createExchangingPool(lpToken.address, currentBlock.number + 5, { from: admin })
    id = 0
  })

  it('should fail to mintExchangingPool that not exists', async () => {
    await expectRevert(distributor.mintExchangingPool(100, balance, { from: user }))
  })

  it('should fail to mintExchangingPool before startBlock', async () => {
    await expectRevert(distributor.mintExchangingPool(id, balance, { from: user }))
  })

  it('should fail to mintExchangingPool without approval', async () => {
    currentBlock = await advanceBlocks(5)
    await expectRevert(distributor.mintExchangingPool(id, balance, { from: user }))
  })

  it('should fail to mintExchangingPool with insuffient funds', async () => {
    await lpToken.approve(distributor.address, balance, { from: user })
    await expectRevert(distributor.mintExchangingPool(id, balance + 1, { from: user }))
  })

  it('should success to mintExchangingPool', async () => {
    await distributor.mintExchangingPool(id, balance, { from: user })
    assert.equal(await lpToken.balanceOf(user), 0)

    let pool = await distributor.getPool(id)
    assert.equal(pool.accumulatedPower, balance)
    assert.equal(pool.tokenAddr, lpToken.address)

    let record = await distributor.getAccountRecord(user, id)
    assert.equal(record.power, balance)
  })
})

contract('Distributor:claim', () => {
  let market
  let lpToken
  let id1
  let id2
  let user
  const lendingPower = 1000e8
  const balance = 1000e8
  let currentBlock

  before('initialize Distributor', async () => {
    await initializeContracts()
    market = accounts[1]
    user = accounts[2]

    lpToken = await MockErc20.deployed()
    await lpToken.transfer(user, balance, { from: admin })
    assert.equal(await lpToken.balanceOf(user), balance)

    await lpToken.approve(distributor.address, balance, { from: user })

    await controller.addMarket(market)
    currentBlock = await web3.eth.getBlock('latest')
    await distributor.createLendingPool(market, currentBlock.number + 5, { from: admin })
    id1 = 0

    await distributor.createExchangingPool(lpToken.address, currentBlock.number + 5, { from: admin })
    id2 = 1
  })

  it('should fail to claim if the pool is not active', async () => {
    await expectRevert(distributor.claim(id1, { from: user }))
    await expectRevert(distributor.claim(id2, { from: user }))
  })

  it('should fail to claim from pool which is not exists', async () => {
    currentBlock = await advanceBlocks(5)
    await distributor.updateLendingPower(user, lendingPower, { from: market })
    await distributor.mintExchangingPool(id2, balance, { from: user })
    await expectRevert(distributor.claim(100, { from: user }))
  })

  it('should success to claim', async () => {
    await distributor.claim(id1, { from: user })
    await distributor.claim(id2, { from: user })

    const minedBlocks = 3
    const poolNum = 2
    const minedAmount = (REWARDS_PER_BLOCK / poolNum) * minedBlocks
    assert.equal(await rds.balanceOf(user), minedAmount * 2)

    const record1 = await distributor.getAccountRecord(user, id1)
    assert.equal(record1.claimed, minedAmount)

    const record2 = await distributor.getAccountRecord(user, id2)
    assert.equal(record2.claimed, minedAmount)
    // claim only RDS, not lpToken
    assert.equal(await lpToken.balanceOf(user), 0)
  })
})

contract('Distributor:exitExchangingPool', () => {
  let lpToken
  let id
  let user
  const balance = 1000e8
  let currentBlock

  before('initialize Distributor', async () => {
    await initializeContracts()
    user = accounts[1]

    lpToken = await MockErc20.deployed()
    await lpToken.transfer(user, balance, { from: admin })
    assert.equal(await lpToken.balanceOf(user), balance)

    await lpToken.approve(distributor.address, balance, { from: user })

    currentBlock = await web3.eth.getBlock('latest')
    await distributor.createExchangingPool(lpToken.address, currentBlock.number + 5, { from: admin })
    id = 0
  })

  it('should fail to exit if the pool is not active', async () => {
    await expectRevert(distributor.exitExchangingPool(id, { from: user }))
  })

  it('should fail to exit from pool which is not exists', async () => {
    currentBlock = await advanceBlocks(5)
    await distributor.mintExchangingPool(id, balance, { from: user })
    await expectRevert(distributor.exitExchangingPool(100, { from: user }))
  })

  it('should success to claim', async () => {
    await distributor.exitExchangingPool(id, { from: user })

    const minedBlocks = 2
    const poolNum = 1
    const minedAmount = (REWARDS_PER_BLOCK / poolNum) * minedBlocks
    assert.equal(await rds.balanceOf(user), minedAmount)

    const record = await distributor.getAccountRecord(user, id)
    assert.equal(record.claimed, minedAmount)

    // should return the lpToken
    assert.equal(await lpToken.balanceOf(user), balance)
  })
})
