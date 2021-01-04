const { advanceBlocks } = require('../util/advance')
const { expectRevert } = require('../util/expect')
const MockController = artifacts.require('MockController')
const MockOrchestrator = artifacts.require('MockOrchestrator')
const Council = artifacts.require('Council')

const STATE_PENDING = 1
const STATE_QUEUED = 4
const STATE_CANCELED = 5
const STATE_EXECUTED = 6

let accounts
let admin
let controller
let orchestrator
let council

async function deployContracts() {
  accounts = await web3.eth.getAccounts()
  admin = accounts[0]

  controller = await MockController.deployed()
  orchestrator = await MockOrchestrator.deployed()
  council = await Council.deployed()
}

async function initializeContracts() {
  await deployContracts()

  await orchestrator.setMarketController(controller.address)
  await orchestrator.setCouncil(council.address)

  await controller.initialize(orchestrator.address)
  await council.initialize(orchestrator.address)
}

async function setupContracts() {
  await initializeContracts()
  await council.startNewTerm(accounts.slice(1, 6))
}

contract('Council:initialize', () => {
  before('initialize contracts', initializeContracts)

  it('check initial states', async () => {
    const members = await council.getMembers()
    assert.equal(members.length, 3)

    const proposalCount = await council.proposalCount()
    assert.equal(proposalCount.toNumber(), 0)
  })
})

contract('Council:propose', () => {
  before('initialize contracts', setupContracts)

  it('should fail to propose with zero delay', async () => {
    await expectRevert(council.propose(council.address, 0, '', '0x', 0, 40320, '', { from: accounts[1] }))
  })

  it('should fail to propose with too large delay', async () => {
    await expectRevert(council.propose(council.address, 0, '', '0x', 57600 + 1, 40320, '', { from: accounts[2] }))
  })

  it('should fail to propose with too small voting period', async () => {
    await expectRevert(council.propose(council.address, 0, '', '0x', 1, 40320 - 1, '', { from: accounts[3] }))
  })

  it('should fail to propose with too large voting period', async () => {
    await expectRevert(council.propose(council.address, 0, '', '0x', 1, 172800 + 1, '', { from: accounts[3] }))
  })

  it('should success to propose', async () => {
    const desc = 'hello defi'
    await council.propose(council.address, 0, '', '0x', 1, 40320, desc, { from: accounts[1] })
    const proposal = await council.getProposal(1)
    assert.equal(proposal.id, 1)
    assert.equal(proposal.ayes, 1)
    assert.equal(proposal.proposer, accounts[1])
    assert.equal(proposal.state, STATE_PENDING)
    assert.equal(proposal.eta, 0)

    const events = await council.getPastEvents('ProposalCreated')
    assert.equal(events.length, 1)
    assert.equal(events[0].args.desc, desc)
  })
})

contract('Council:vote', () => {
  const votingDelay = 5

  before('initialize contracts', async () => {
    await setupContracts()
    await council.propose(council.address, 0, '', '0x', votingDelay, 40320, '', { from: accounts[1] })
  })

  it('should fail to vote on a not exsited proposal', async () => {
    await expectRevert(council.vote(999, { from: accounts[1] }))
  })

  it('should fail to vote before if voting time not up', async () => {
    await expectRevert(council.vote(1, { from: accounts[1] }))
  })

  it('should success to vote after voting start time', async () => {
    await advanceBlocks(votingDelay)
    await council.vote(1, { from: accounts[2] })
    const proposal = await council.getProposal(1)
    assert.equal(proposal.ayes, 2)
  })

  it('should fail to vote more that once by the same member', async () => {
    await expectRevert(council.vote(1, { from: accounts[1] }))
    await expectRevert(council.vote(1, { from: accounts[2] }))
  })

  it('should success to queue the proposal', async () => {
    await council.vote(1, { from: accounts[3] })
    const proposal = await council.getProposal(1)
    assert.equal(proposal.state, STATE_QUEUED)
    assert.equal(proposal.ayes, 3)

    const currentBlock = await web3.eth.getBlock('latest')
    assert.equal(proposal.eta, currentBlock.number + 11520)
  })

  it('should fail to vote queued proposal', async () => {
    await expectRevert(council.vote(1, { from: accounts[4] }))
  })

  it('should fail to vote expired proposal', async () => {
    // Should test after adjusting MIN_VOTING_PERIOD
    // const votingPeriod = 10
    // await council.propose(council.address, 0, '', '0x', votingDelay, votingPeriod, '', { from: accounts[1] })
    // await advanceBlocks(votingPeriod + votingPeriod + 1)
    // await expectRevert(council.vote(2, { from: accounts[4] }))
  })
})

contract('Council:cancel', () => {
  const votingDelay = 5

  before('initialize contracts', async () => {
    await setupContracts()
  })

  it('should fail to cancel without permission', async () => {
    await expectRevert(council.cancel(1, { from: accounts[1] }))
  })

  it('should fail to cancel a not exsited proposal', async () => {
    await expectRevert(council.cancel(999, { from: admin }))
  })

  it('should success to cancel a pending proposal', async () => {
    await council.propose(council.address, 0, '', '0x', votingDelay, 40320, '', { from: accounts[1] })

    let proposal = await council.getProposal(1)
    assert.equal(proposal.state, STATE_PENDING)
    await council.cancel(1, { from: admin })
    proposal = await council.getProposal(1)
    assert.equal(proposal.state, STATE_CANCELED)

    const events = await council.getPastEvents('ProposalCanceled')
    assert.equal(events.length, 1)
    assert.equal(events[0].args.id, 1)
    assert.equal(events[0].args.success, true)
  })

  it('should success to cancel a queued proposal', async () => {
    await council.propose(council.address, 0, '', '0x', votingDelay, 40320, '', { from: accounts[1] })
    await advanceBlocks(votingDelay)
    await council.vote(2, { from: accounts[2] })
    await council.vote(2, { from: accounts[3] })

    let proposal = await council.getProposal(2)
    assert.equal(proposal.state, STATE_QUEUED)
    await council.cancel(2, { from: admin })
    proposal = await council.getProposal(2)
    assert.equal(proposal.state, STATE_CANCELED)

    const events = await council.getPastEvents('ProposalCanceled')
    // The previous events may be cleared by the ganache, so it's a little unexpected
    assert.equal(events.length, 1)
    assert.equal(events[0].args.id, 2)
    assert.equal(events[0].args.success, true)
  })
})

contract('Council:execute', () => {
  const executionDelay = 3
  const votingDelay = 5
  const writeVal = '12345'

  before('initialize contracts', async () => {
    await setupContracts()

    await council.setExecutionDelay(executionDelay, { from: admin })

    const signature = 'writeByCouncil(uint256)'
    const params = web3.eth.abi.encodeParameter('uint256', writeVal)
    await council.propose(controller.address, 0, signature, params, votingDelay, 40320, '', {
      from: accounts[1],
    })
    await advanceBlocks(votingDelay)

    const id = 1
    await council.vote(id, { from: accounts[2] })
    await council.vote(id, { from: accounts[3] })
    const proposal = await council.getProposal(id)
    assert.equal(proposal.state, STATE_QUEUED)
  })

  it('should fail to execute the proposal before ETA', async () => {
    await expectRevert(council.execute(1, { from: accounts[1] }))
  })

  it('should fail to execute not existed proposal', async () => {
    await expectRevert(council.execute(999, { from: accounts[1] }))
  })

  it('should success to execute the proposal afte ETA', async () => {
    await advanceBlocks(executionDelay)
    await council.execute(1, { from: accounts[1] })
    assert.equal((await controller.val()).toString(), writeVal)

    const proposal = await council.getProposal(1)
    assert.equal(proposal.state, STATE_EXECUTED)
  })

  it('should fail to vote executed proposal', async () => {
    await expectRevert(council.vote(1, { from: accounts[4] }))
  })

  it('should fail to execute executed proposal', async () => {
    await expectRevert(council.execute(1, { from: accounts[1] }))
  })

  it('should fail to cancel executed proposal', async () => {
    await council.cancel(1, { from: admin })
    const events = await council.getPastEvents('ProposalCanceled')
    assert.equal(events.length, 1)
    assert.equal(events[0].args.success, false)
  })
})
