const { expectRevert } = require('../util/expect')
const RDS = artifacts.require('RDS')
const MockOrchestrator = artifacts.require('MockOrchestrator')

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

const MAX_SUPPLY = (100000000e8).toString()
const INITIAL_ISSUE = (20000000e8).toString()

let rds
let admin
let superior
let accounts
let orchestrator

async function deployContracts() {
  accounts = await web3.eth.getAccounts()
  admin = accounts[0]
  superior = accounts[1]
  rds = await RDS.deployed()
  orchestrator = await MockOrchestrator.deployed()
}

async function initializeContracts() {
  await deployContracts()

  await orchestrator.setCouncil(admin)
  await rds.initialize(orchestrator.address)
  await rds.setSuperior(superior)
}

contract('RDS:deploy', () => {
  before('deply RDS', deployContracts)

  it('should transfer the initial supply tokens to the deployer', async () => {
    const decimals = await rds.decimals()
    assert.equal(decimals, 8)

    const maxSupply = await rds.maxSupply()
    assert.equal(maxSupply.toString(), MAX_SUPPLY)

    const totalSupply = await rds.totalSupply()
    assert.equal(totalSupply.toString(), INITIAL_ISSUE)

    const adminBalance = await rds.balanceOf(admin)
    assert.equal(adminBalance.toString(), INITIAL_ISSUE)
  })
})

contract('RDS:mint', () => {
  before('setup RDS contract', deployContracts)

  it('should fail to mint for the admin account', async () => {
    await expectRevert(rds.mint(accounts[2], 1e8))
  })

  it('should be ok minting by the superior', async () => {
    const user = accounts[2]
    await orchestrator.setCouncil(admin)
    await rds.initialize(orchestrator.address)
    await expectRevert(rds.initialize(user))

    await rds.setSuperior(superior)

    const mintAmount = 100e8
    await rds.mint(user, mintAmount, { from: superior })
    assert.equal(await rds.balanceOf(user), mintAmount)
  })

  it('should fail to mint if exceeding the max supply', async () => {
    await expectRevert(rds.mint(accounts[2], MAX_SUPPLY, { from: superior }))
  })

  it('should fail to mint to zero address', async () => {
    await expectRevert(rds.mint(ZERO_ADDRESS, 1e8, { from: superior }))
  })
})

contract('RDS:burn', () => {
  let user1
  const amount = 100e8

  before('initialize RDS contract', async () => {
    await initializeContracts()
    user1 = accounts[2]
    await rds.transfer(user1, amount, { from: admin })
    assert.equal(await rds.balanceOf(user1), amount)
  })

  it('should fail to burn if balance is insufficient', async () => {
    await expectRevert(rds.burn(user1, 101e8, { from: user1 }))
  })

  it('should fail to burn if allowance is insufficient', async () => {
    await rds.approve(admin, 10e8, { from: user1 })
    await expectRevert(rds.burn(user1, 11e8, { from: admin }))
  })

  it('should be ok burning if balance is sufficient', async () => {
    await rds.burn(user1, 11e8, { from: user1 })
    assert.equal(await rds.balanceOf(user1), 89e8)
  })

  it('should be ok burning if allowance is sufficient', async () => {
    await rds.burn(user1, 9e8, { from: admin })
    assert.equal(await rds.allowance(user1, admin), 1e8)
    assert.equal(await rds.balanceOf(user1), 80e8)
  })

  it('should fail to burn from zero address', async () => {
    await expectRevert(rds.burn(ZERO_ADDRESS, 1e8, { from: user1 }))
  })
})

contract('RDS:transfer', () => {
  let user1
  const amount = 100e8

  before('initialize RDS contract', async () => {
    await initializeContracts()
    user1 = accounts[2]

    await rds.transfer(user1, amount, { from: admin })
    assert.equal(await rds.balanceOf(user1), amount)

    await rds.approve(admin, 10e8, { from: user1 })
    assert.equal(await rds.allowance(user1, admin), 10e8)
  })

  it('should fail to transfer if balance is insufficient', async () => {
    await expectRevert(rds.transfer(admin, 101e8, { from: user1 }))
  })

  it('should fail to transfer if allowance is insufficient', async () => {
    await expectRevert(rds.transferFrom(user1, admin, 11e8, { from: admin }))
  })

  it('should be ok to transfer if balance is sufficient', async () => {
    await rds.transfer(admin, 11e8, { from: user1 })
    assert.equal(await rds.balanceOf(user1), 89e8)
  })

  it('should be ok to transfer if allowance is sufficient', async () => {
    await rds.transferFrom(user1, admin, 9e8, { from: admin })
    assert.equal(await rds.allowance(user1, admin), 1e8)
    assert.equal(await rds.balanceOf(user1), 80e8)
  })

  it('should fail to transfer from zero address', async () => {
    await expectRevert(rds.transferFrom(ZERO_ADDRESS, user1, 1e8, { from: user1 }))
  })

  it('should fail to transfer to zero address', async () => {
    await expectRevert(rds.transfer(ZERO_ADDRESS, 1e8, { from: user1 }))
  })
})

contract('RDS:approve', () => {
  before('initialize RDS contract', async () => {
    await initializeContracts()
  })

  it('should fail to approve to zero address', async () => {
    await expectRevert(rds.transfer(ZERO_ADDRESS, 1e8, { from: admin }))
  })
})
