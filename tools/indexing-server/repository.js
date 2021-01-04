/**
 * Module responsibilities:
 * 1. Create/update account docs
 * 2. Retrieve top accounts sorted by B-S ratio
 *
 * Account model
 *   - address: String
 *   - balance: { rETH: Number, rDOL: Number }
 *   - borrowed: { rETH: Number, rDOL: Number }
 *   - liquidity: Number
 *   - updatedAt: Date
 */

const assert = require('assert')
const { promisify } = require('util')
const path = require('path')
const fs = require('fs')
const Datastore = require('nedb')

class Repository {
  constructor(options) {
    assert(options)
    assert(options.dataDir)
    if (!fs.existsSync(options.dataDir)) {
      fs.mkdirSync(options.dataDir)
    }
    const filename = path.join(options.dataDir, 'accounts.db')
    this.accountStore = new Datastore({ filename, autoload: true })
    this.queue = []
    this.isProcessing = false
  }

  async initialize() {
    await this.ensureIndexAsync({ fieldName: 'account', unique: true })
    await this.ensureIndexAsync({ fieldName: 'updatedAt' })
  }

  start() {
    setInterval(() => {
      if (this.queue.length > 0) {
        this.processAll()
      }
    }, 100)
  }

  createOrUpdateAccount(data) {
    this.queue.push(data)
  }

  findStaleAccounts(limit, staleSeconds) {
    const time = Date.now() - staleSeconds * 1000
    return new Promise((resolve, reject) => {
      this.accountStore
        .find({ updatedAt: { $lte: time } })
        .sort({ updatedAt: 1 })
        .limit(limit)
        .exec((err, docs) => {
          if (err) return reject(err)
          return resolve(docs)
        })
    })
  }

  async getDangerousAccounts(skip, limit) {
    const count = await this.countAsync({})
    return new Promise((resolve, reject) => {
      this.accountStore
        .find({})
        .sort({ liquidity: 1 })
        .skip(skip)
        .limit(limit)
        .exec((err, docs) => {
          if (err) return reject(err)
          return resolve({ count, docs })
        })
    })
  }

  async processAll() {
    if (this.isProcessing) return
    this.isProcessing = true
    while (this.queue.length > 0) {
      const data = this.queue.shift()
      await this.processOne(data)
    }
    this.isProcessing = false
  }

  async processOne(data) {
    const { account, symbol, liquidity, balance, borrowed } = data
    const count = await this.countAsync({ account })
    // console.log('account:', account, count)
    if (count > 0) {
      const query = { account }
      const modifier = { $set: {} }
      modifier.$set['liquidity'] = liquidity
      modifier.$set[`collaterals.${symbol}`] = balance
      modifier.$set[`borrows.${symbol}`] = borrowed
      modifier.$set['updatedAt'] = Date.now()
      // console.log('update:', query, modifier)
      await this.updateAsync(query, modifier, {})
    } else {
      const collaterals = {}
      collaterals[symbol] = balance
      const borrows = {}
      borrows[symbol] = borrowed
      const doc = { account, collaterals, borrows, liquidity, updatedAt: Date.now() }
      // console.log('insert:', doc)
      await this.insertAsync(doc)
    }
  }

  countAsync(query) {
    return promisify(this.accountStore.count.bind(this.accountStore))(query)
  }

  insertAsync(doc) {
    return promisify(this.accountStore.insert.bind(this.accountStore))(doc)
  }

  updateAsync(query, modifier, options) {
    return promisify(this.accountStore.update.bind(this.accountStore))(query, modifier, options)
  }

  ensureIndexAsync(params) {
    return promisify(this.accountStore.ensureIndex.bind(this.accountStore))(params)
  }
}

module.exports = Repository
