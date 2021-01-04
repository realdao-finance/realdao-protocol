/**
 * Module responsibilities:
 * 1. Create/update proposal docs
 *
 */

const assert = require('assert')
const { promisify } = require('util')
const path = require('path')
const fs = require('fs')
const Datastore = require('nedb')

class CouncilRepository {
  constructor(options) {
    assert(options)
    assert(options.dataDir)
    if (!fs.existsSync(options.dataDir)) {
      fs.mkdirSync(options.dataDir)
    }
    const proposalStoreFile = path.join(options.dataDir, 'council_proposals.db')
    const voterStoreFile = path.join(options.dataDir, 'council_voters.db')
    this.proposalStore = new Datastore({ filename: proposalStoreFile, autoload: true })
    this.voterStore = new Datastore({ filename: voterStoreFile, autoload: true })
    this.queue = []
    this.isProcessing = false
  }

  async initialize() {
    await this.ensureIndexAsync(this.proposalStore, { fieldName: 'pid', unique: true })
    await this.ensureIndexAsync(this.proposalStore, { fieldName: 'state' })
    await this.ensureIndexAsync(this.voterStore, { fieldName: 'pid' })
  }

  addProposal(data) {
    return this.insertAsync(this.proposalStore, data)
  }

  addProposalVoter(pid, voter) {
    return this.insertAsync(this.voterStore, { pid, voter })
  }

  updateProposal(pid, updates) {
    const modifier = { $set: {} }
    for (const key in updates) {
      modifier.$set[key] = updates[key]
    }
    return this.updateAsync(this.proposalStore, { pid }, modifier, {})
  }

  async getProposals(state, skip, limit) {
    let query = {}
    if (state !== 0) {
      query.state = state
    }
    const count = await this.countAsync(this.proposalStore, query)
    return new Promise((resolve, reject) => {
      this.proposalStore
        .find(query)
        .sort({ pid: -1 })
        .skip(skip)
        .limit(limit)
        .exec((err, docs) => {
          if (err) return reject(err)
          return resolve({ count, docs })
        })
    })
  }

  async getProposalDetail(pid) {
    const proposal = await this.findOneAsync(this.proposalStore, { pid })
    if (!proposal) return null
    const voters = await new Promise((resolve, reject) => {
      this.voterStore.find({ pid }).exec((err, docs) => {
        if (err) return reject(err)
        return resolve(docs)
      })
    })
    return { proposal, voters }
  }

  findOneAsync(collection, query) {
    return promisify(collection.findOne.bind(collection))(query)
  }

  countAsync(collection, query) {
    return promisify(collection.count.bind(collection))(query)
  }

  insertAsync(collection, doc) {
    return promisify(collection.insert.bind(collection))(doc)
  }

  updateAsync(collection, query, modifier, options) {
    return promisify(collection.update.bind(collection))(query, modifier, options)
  }

  ensureIndexAsync(collection, params) {
    return promisify(collection.ensureIndex.bind(collection))(params)
  }
}

module.exports = CouncilRepository
