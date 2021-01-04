/**
 * Module responsibilities:
 * 1. Add retrieval task to the queue
 * 2. Consume the tasks: retrieve account liquidity, balances and borrowed
 */

const assert = require('assert')
const EventEmitter = require('events')

class RetrievalWorker extends EventEmitter {
  constructor(options) {
    assert(options)
    assert(options.realdao)
    assert(options.realdao.controller)
    super()
    this.options = options
    this.queue = []
    this.pendingKeys = new Map()
    this.isRetrieving = false
  }

  async initialize() {}

  start() {
    setInterval(() => {
      if (this.queue.length > 0) {
        this.retrieveAll()
      }
    }, 1000)
  }

  async retrieveAll() {
    if (this.isRetrieving) return
    this.isRetrieving = true
    while (this.queue.length > 0) {
      const task = this.queue.shift()
      await this.retrieveOne(task.address, task.symbol, task.account)
    }
    this.isRetrieving = false
  }

  async retrieveOne(address, symbol, account) {
    const controller = this.options.realdao.controller()
    const reporter = this.options.realdao.reporter()
    const results = await Promise.all([
      controller.getAccountLiquidity(account).call(),
      reporter.getRTokenBalances(address, account).call(),
    ])
    let liquidity = Number(results[0][0]) / 1e8
    const shortfall = Number(results[0][1]) / 1e8
    liquidity = shortfall > 0 ? shortfall * -1 : liquidity

    const balance = Number(results[1].balanceOf) / 1e8
    const borrowed = Number(results[1].borrowBalanceCurrent) / 10 ** Number(results[1].underlyingDecimals)
    this.emit('AccountRetrieved', { symbol, account, liquidity, balance, borrowed })
  }

  addTask(address, symbol, account) {
    const key = symbol + ':' + account
    if (this.pendingKeys.get(key)) return
    this.pendingKeys.set(key, true)
    this.queue.push({ address, symbol, account })
  }
}

module.exports = RetrievalWorker
