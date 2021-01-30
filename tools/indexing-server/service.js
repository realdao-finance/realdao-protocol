/**
 * Module responsibilities:
 * 1. Subscribe account change events, re-calculate account liquidity and B-S ratio and then write to db
 * 2. Re-calculate the liquidity of the accounts which has not been updated within a certain period of time
 */

const assert = require('assert')
const Web3 = require('web3')
const { RealDAO } = require('../../sdk')
const RetrievalWorker = require('./retrieval-worker')
const Repository = require('./repository')
const CouncilRepository = require('./council-repository')
const TokenManager = require('./token-manager')
const CouncilObserver = require('./council-observer')
const PriceFeeder = require('./price-feeder')
const constants = require('./constants')

const env = require('../../.env.js')

class Service {
  constructor(options) {
    assert(options)
    assert(options.dataDir)
    this.options = options
    this.realdao = new RealDAO({
      Web3,
      env: env.current,
      provider: env.networks[env.current].provider,
      orchestrator: env.networks[env.current].orchestrator,
    })
  }

  async initialize() {
    await this.realdao.loadRTokens()
    await this.realdao.loadReporter()
    await this.realdao.loadController()
    await this.realdao.loadCouncil()
    await this.realdao.loadOracle()

    global.web3 = this.realdao._web3

    const dataDir = this.options.dataDir
    this.accountRepo = new Repository({ dataDir })
    this.tokenManager = new TokenManager({ realdao: this.realdao, dataDir })
    this.retrievalWorker = new RetrievalWorker({ realdao: this.realdao })

    this.councilRepo = new CouncilRepository({ dataDir })
    const councilContract = this.realdao.council(true)
    this.councilObserver = new CouncilObserver({ dataDir, councilContract, councilRepo: this.councilRepo })

    this.priceFeeder = new PriceFeeder({ oracleContract: this.realdao.oracle() })

    await this.accountRepo.initialize()
    await this.councilRepo.initialize()
    await this.tokenManager.initialize()
    await this.retrievalWorker.initialize()
    await this.councilObserver.initialize()
    await this.priceFeeder.initialize()
    this.priceFeeder.setAdminKey(env.privateKey)

    this.retrievalWorker.on('AccountRetrieved', (msg) => {
      this.accountRepo.createOrUpdateAccount(msg)
    })

    this.tokenManager.on('AccountChanged', (msg) => {
      this.retrievalWorker.addTask(msg.address, msg.symbol, msg.account)
    })
  }

  start() {
    this.accountRepo.start()
    this.retrievalWorker.start()
    this.tokenManager.start()
    this.councilObserver.start()
    this.priceFeeder.start()

    setInterval(() => {
      this.refresh()
    }, 5000)
  }

  getDangerousAccounts(skip, limit) {
    return this.accountRepo.getDangerousAccounts(skip, limit)
  }

  getCouncilProposals(state, skip, limit) {
    return this.councilRepo.getProposals(state, skip, limit)
  }

  getCouncilProposalDetail(id) {
    return this.councilRepo.getProposalDetail(id)
  }

  async refresh() {
    const refreshLimit = this.options.refreshLimit || 200
    const staleThreshold = this.options.staleThreshold || 300 // 5 minutes
    const staleAccounts = await this.accountRepo.findStaleAccounts(refreshLimit, staleThreshold)
    for (const item of staleAccounts) {
      const account = item.account
      for (const symbol in item.balance) {
        const address = this.tokenManager.getTokenAddress(symbol)
        this.retrievalWorker.addTask(address, symbol, account)
      }
    }
  }
}

module.exports = Service
