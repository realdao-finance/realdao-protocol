/**
 * Module responsibilities:
 * 1. Polling the RToken events
 * 2. Retrieve the latest account snapshot
 * 3. Emit account change event
 * 4. Cache the RToken metadata, such as decimals and exchange rate.
 *
 * Account change event example:
 *  { symbol: 'rETH',  address: '...',  'account': '...'}
 */

const assert = require('assert')
const fs = require('fs')
const path = require('path')
const EventEmitter = require('events')

class TokenObserver extends EventEmitter {
  constructor(options) {
    assert(options)
    assert(options.tokenContract)
    assert(options.dataDir)
    super()
    this.options = options
    this.isPolling = false
    this.symbol = ''
    this.address = this.options.tokenContract.options.address
  }

  async initialize() {
    this.symbol = await this.options.tokenContract.methods.symbol().call()
    this.lastCheckPointFile = path.join(this.options.dataDir, `${this.symbol}.checkpoint`)
    this.lastCheckPoint = this.readLastCheckPoint()
    console.log('got token symbol:', this.symbol)
  }

  start() {
    const tokenContract = this.options.tokenContract
    this.pollPastEvents().then(() => {
      tokenContract.events.allEvents({ fromBlock: this.lastCheckPoint }, (error, event) => {
        if (error) {
          console.log('market event subscriber error:', error)
          process.exit(0)
          return
        }
        // console.log('receive new market event:', event)
        this.pollPastEvents()
      })
    })
  }

  async pollPastEvents() {
    if (this.isPolling) return
    this.isPolling = true
    const lastBlock = await web3.eth.getBlock('latest')
    console.log(`polling past token events from block ${this.lastCheckPoint} to ${lastBlock.number}`)
    const events = await this.options.tokenContract.getPastEvents({
      fromBlock: this.lastCheckPoint + 1,
      toBlock: lastBlock.number,
    })
    console.log(`${events.length} events polled for ${this.symbol}`)
    this.processEvents(events)
    this.lastCheckPoint = lastBlock.number
    this.saveLastCheckPoint()
    this.isPolling = false
  }

  processEvents(events) {
    for (const event of events) {
      const topic = event.event
      const values = event.returnValues
      switch (topic) {
        case 'Mint':
          this.emitAccountChange(values.minter)
          break
        case 'Redeem':
          this.emitAccountChange(values.redeemer)
          break
        case 'Borrow':
          this.emitAccountChange(values.borrower)
          break
        case 'RepayBorrow':
          this.emitAccountChange(values.payer)
          this.emitAccountChange(values.borrower)
          break
        case 'LiquidateBorrow':
          this.emitAccountChange(values.liquidator)
          this.emitAccountChange(values.borrower)
          break
        case 'Transfer':
          this.emitAccountChange(values.from)
          this.emitAccountChange(values.to)
          break
      }
    }
  }

  emitAccountChange(account) {
    if (account == this.address) return
    this.emit('AccountChanged', { symbol: this.symbol, address: this.address, account })
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

module.exports = TokenObserver
