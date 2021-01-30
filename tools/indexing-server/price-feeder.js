const assert = require('assert')
const request = require('request')
const Agent = require('socks5-https-client/lib/Agent')

const exchangeBaseUrl = 'https://api.huobi.pro/market/detail'
const feedConfig = [
  {
    contractSymbol: 'HBTC',
    exchangeSymbol: 'btcusdt',
  },
  {
    contractSymbol: 'HETH',
    exchangeSymbol: 'ethusdt',
  },
  {
    contractSymbol: 'WHT',
    exchangeSymbol: 'htusdt',
  },
]
const PRICE_MANTISSA = 1e8

class PriceFeeder {
  constructor(options) {
    assert(options)
    assert(options.oracleContract)
    this.oracleContract = options.oracleContract
    this.adminAddress = null
    this.feedInterval = options.feedInterval || 10000
    this.useAgent = options.useAgent || true
    this.agentOptions = options.agentOptions || {
      socksHost: '127.0.0.1',
      socksPort: 1080,
    }
    this.feedTimer = null
  }

  async initialize() {}

  start() {
    const fetchPriceAndFeed = this._fetchPriceAndFeed.bind(this)
    this.feedTimer = setInterval(fetchPriceAndFeed, this.feedInterval)
    fetchPriceAndFeed()
  }

  stop() {
    if (!this.feedTimer) {
      clearInterval(this.feedTimer)
    }
  }

  setAdminKey(key) {
    const account = web3.eth.accounts.wallet.add(key)
    this.adminAddress = account.address
    console.log('add key for account:', this.adminAddress)
  }

  async _fetchPriceAndFeed() {
    if (!this.adminAddress) {
      console.log('admin key no set')
      return
    }
    const urls = feedConfig.map((item) => `${exchangeBaseUrl}?symbol=${item.exchangeSymbol}`)
    const tasks = urls.map((url) => {
      return new Promise((resolve, reject) => {
        const requestOptions = { url }
        if (this.useAgent && this.agentOptions) {
          requestOptions.agentClass = Agent
          requestOptions.agentOptions = this.agentOptions
        }
        request(requestOptions, (err, res, body) => {
          if (err) return reject(err)
          resolve(JSON.parse(body))
        })
      })
    })
    try {
      const responses = await Promise.all(tasks)
      const symbols = []
      const prices = []
      for (let i = 0; i < feedConfig.length; i++) {
        const { contractSymbol } = feedConfig[i]
        const marketResponse = responses[i]
        if (marketResponse.status !== 'ok') {
          console.log('market request failed:', marketResponse)
        }
        const price = Math.floor(Number(marketResponse.tick.close) * PRICE_MANTISSA).toString()
        console.log(`get price for ${contractSymbol}: ${price}`)
        symbols.push(contractSymbol)
        prices.push(price)
      }
      const txRes = await this.oracleContract
        .setUnderlyingPrices(symbols, prices)
        .send({ from: this.adminAddress, gas: 4000000 })
      console.log('fetchPriceAndFeed success:', txRes.transactionHash)
    } catch (e) {
      console.log('fetchPriceAndFeed exception:', e)
    }
  }
}

module.exports = PriceFeeder
