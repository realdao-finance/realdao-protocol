const assert = require('assert')
const TokenObserver = require('./token-observer')

class TokenManager {
  constructor(options) {
    assert(options)
    assert(options.realdao)
    assert(options.dataDir)
    this.options = options
    this.tokenObs = []
    for (const symbol in options.realdao._rTokens) {
      const tokenContract = options.realdao.rToken(symbol, true)
      this.tokenObs.push(new TokenObserver({ tokenContract, dataDir: options.dataDir }))
    }
    this.symbolAddrMap = new Map()
  }

  async initialize() {
    for (const obs of this.tokenObs) {
      await obs.initialize()
      this.symbolAddrMap.set(obs.symbol, obs.address)
    }
  }

  getTokenAddress(symbol) {
    return this.symbolAddrMap.get(symbol)
  }

  on(event, handler) {
    for (const obs of this.tokenObs) {
      obs.on(event, handler)
    }
  }

  start() {
    for (const obs of this.tokenObs) {
      obs.start()
    }
  }
}

module.exports = TokenManager
