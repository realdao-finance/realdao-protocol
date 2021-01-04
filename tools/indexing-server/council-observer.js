/**
 * Module responsibilities:
 * Poll council proposal events and save to database
 */

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const EventEmitter = require('events')
const ProposalState = require('./constants').CouncilProposalState

class CouncilObserver extends EventEmitter {
  constructor(options) {
    assert(options)
    assert(options.councilContract)
    assert(options.councilRepo)
    assert(options.dataDir)
    super()
    this.options = options
    this.lastCheckPointFile = path.join(options.dataDir, 'council.checkpoint')
    this.lastCheckPoint = this.readLastCheckPoint()
    this.isPolling = false
  }

  async initialize() {}

  start() {
    const councilContract = this.options.councilContract
    this.pollPastEvents().then(() => {
      councilContract.events.allEvents({ fromBlock: this.lastCheckPoint }, (error, event) => {
        if (error) {
          console.log('council event subscriber error:', error)
          process.exit(0)
          return
        }
        // console.log('receive new council event:', event)
        this.pollPastEvents()
      })
    })
  }

  async pollPastEvents() {
    if (this.isPolling) return
    this.isPolling = true
    const lastBlock = await web3.eth.getBlock('latest')
    console.log(`polling past council events from block ${this.lastCheckPoint} to ${lastBlock.number}`)
    const events = await this.options.councilContract.getPastEvents({
      fromBlock: this.lastCheckPoint + 1,
      toBlock: lastBlock.number,
    })
    await this.processEvents(events)
    this.lastCheckPoint = lastBlock.number
    this.saveLastCheckPoint()
    this.isPolling = false
  }

  async processEvents(events) {
    const councilRepo = this.options.councilRepo
    for (const event of events) {
      const topic = event.event
      const values = event.returnValues
      console.log('processEvent topic:', topic)
      switch (topic) {
        case 'ProposalCreated':
          await councilRepo.addProposal({
            pid: Number(values.id),
            target: values.target,
            value: values.value,
            signature: values.signature,
            params: values.params ? values.params : '',
            proposer: values.proposer,
            startBlock: values.startBlock,
            endBlock: values.endBlock,
            desc: values.desc,
            eta: '0',
            state: ProposalState.Pending,
          })
          break
        case 'ProposalVoted':
          await councilRepo.addProposalVoter(Number(values.id), values.voter)
          break
        case 'ProposalExpired':
          await councilRepo.updateProposal(Number(values.id), { state: ProposalState.Expired })
          break
        case 'ProposalQueued':
          await councilRepo.updateProposal(Number(values.id), { state: ProposalState.Queued, eta: values.eta })
          break
        case 'ProposalExecuted':
          await councilRepo.updateProposal(Number(values.id), { state: ProposalState.Executed })
          break
        case 'ProposalCanceled':
          await councilRepo.updateProposal(Number(values.id), { state: ProposalState.Canceled })
          break
      }
    }
  }

  readLastCheckPoint() {
    if (!fs.existsSync(this.lastCheckPointFile)) {
      return 0
    }
    return Number.parseInt(fs.readFileSync(this.lastCheckPointFile, 'utf8'))
  }

  saveLastCheckPoint() {
    fs.writeFileSync(this.lastCheckPointFile, this.lastCheckPoint.toString(), 'utf8')
  }
}

module.exports = CouncilObserver
