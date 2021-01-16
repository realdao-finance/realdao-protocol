const { expectRevert } = require('../util/expect')
const DOL = artifacts.require('DOL')
const MockOrchestrator = artifacts.require('MockOrchestrator')

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

let dol
let admin
let superior
let accounts
let orchestrator

async function deployContracts() {
  accounts = await web3.eth.getAccounts()
  admin = accounts[0]
  superior = accounts[1]
  dol = await DOL.deployed()
  orchestrator = await MockOrchestrator.deployed()
}

async function initializeContracts() {
  await deployContracts()

  await orchestrator.setCouncil(admin)
  await dol.initialize(orchestrator.address)
  await dol.setSuperior(superior)
  await dol.mint(admin, 10000e8, { from: superior })
}

contract('DOL:deploy', () => {
  before('deply DOL', deployContracts)

  it('check initnial setting', async () => {
    const decimals = await dol.decimals()
    assert.equal(decimals, 8)

    const symbol = await dol.symbol()
    assert.equal(symbol, 'DOL')

    const name = await dol.name()
    assert.equal(name, 'DOL Stablecoin')

    const totalSupply = await dol.totalSupply()
    assert.equal(totalSupply, 0)
  })
})

contract('DOL:mint', () => {
  before('setup DOL contract', initializeContracts)

  it('should be ok minting by the superior', async () => {
    const user = accounts[2]
    await expectRevert(dol.initialize(user))

    const mintAmount = 100e8
    await dol.mint(user, mintAmount, { from: superior })
    assert.equal(await dol.balanceOf(user), mintAmount)
  })

  it('should fail to mint to zero address', async () => {
    await expectRevert(dol.mint(ZERO_ADDRESS, 1e8, { from: superior }))
  })
})

contract('DOL:burn', () => {
  let user1
  const amount = 100e8

  before('initialize DOL contract', async () => {
    await initializeContracts()
    user1 = accounts[2]
    await dol.transfer(user1, amount, { from: admin })
    assert.equal(await dol.balanceOf(user1), amount)
  })

  it('should fail to burn if balance is insufficient', async () => {
    await expectRevert(dol.burn(user1, 101e8, { from: user1 }))
  })

  it('should fail to burn if allowance is insufficient', async () => {
    await dol.approve(admin, 10e8, { from: user1 })
    await expectRevert(dol.burn(user1, 11e8, { from: admin }))
  })

  it('should be ok burning if balance is sufficient', async () => {
    await dol.burn(user1, 11e8, { from: user1 })
    assert.equal(await dol.balanceOf(user1), 89e8)
  })

  it('should be ok burning if allowance is sufficient', async () => {
    await dol.burn(user1, 9e8, { from: admin })
    assert.equal(await dol.allowance(user1, admin), 1e8)
    assert.equal(await dol.balanceOf(user1), 80e8)
  })

  it('should fail to burn from zero address', async () => {
    await expectRevert(dol.burn(ZERO_ADDRESS, 1e8, { from: user1 }))
  })
})

contract('DOL:transfer', () => {
  let user1
  const amount = 100e8

  before('initialize DOL contract', async () => {
    await initializeContracts()
    user1 = accounts[2]

    await dol.transfer(user1, amount, { from: admin })
    assert.equal(await dol.balanceOf(user1), amount)

    await dol.approve(admin, 10e8, { from: user1 })
    assert.equal(await dol.allowance(user1, admin), 10e8)
  })

  it('should fail to transfer if balance is insufficient', async () => {
    await expectRevert(dol.transfer(admin, 101e8, { from: user1 }))
  })

  it('should fail to transfer if allowance is insufficient', async () => {
    await expectRevert(dol.transferFrom(user1, admin, 11e8, { from: admin }))
  })

  it('should be ok to transfer if balance is sufficient', async () => {
    await dol.transfer(admin, 11e8, { from: user1 })
    assert.equal(await dol.balanceOf(user1), 89e8)
  })

  it('should be ok to transfer if allowance is sufficient', async () => {
    await dol.transferFrom(user1, admin, 9e8, { from: admin })
    assert.equal(await dol.allowance(user1, admin), 1e8)
    assert.equal(await dol.balanceOf(user1), 80e8)
  })

  it('should fail to transfer from zero address', async () => {
    await expectRevert(dol.transferFrom(ZERO_ADDRESS, user1, 1e8, { from: user1 }))
  })

  it('should fail to transfer to zero address', async () => {
    await expectRevert(dol.transfer(ZERO_ADDRESS, 1e8, { from: user1 }))
  })
})

contract('DOL:approve', () => {
  before('initialize DOL contract', async () => {
    await initializeContracts()
  })

  it('should fail to approve to zero address', async () => {
    await expectRevert(dol.transfer(ZERO_ADDRESS, 1e8, { from: admin }))
  })
})
