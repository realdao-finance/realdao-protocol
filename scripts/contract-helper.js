const Web3 = require('web3')
const { RealDAO } = require('../sdk')
const env = require('../.env.js')

function from(account, value) {
  return { from: account, gas: 4000000, value }
}

class ContractHelper extends RealDAO {
  async run(cmd, args) {
    await this.loadOrchestrator()
    const accounts = await this._web3.eth.getAccounts()
    this.admin = accounts[0]
    const func = this[cmd].bind(this)
    let result = await func(...args)
    console.log(result)
  }

  async setOrchestrator(addr) {
    return await this.supreme().initialize(addr).send(from(this.admin))
  }

  async getOrchestrator() {
    return await this.supreme().orchestrator().call()
  }

  async initializeOrchestrator(data) {
    await this.loadRDS()
    await this.loadDistributor()

    const params = JSON.parse(data)
    await this.orchestrator()
      .initialize(...params)
      .send(from(this.admin))

    const distributorAddr = this.distributor(true).options.address
    return await this.rds().initialize(distributorAddr).send(from(this.admin))
  }

  async createExchangingPool(token, n) {
    await this.loadDistributor()
    const currentBlock = await this._web3.eth.getBlock('latest')
    const result = await this.distributor()
      .createExchangingPool(token, currentBlock.number + Number(n))
      .send(from(this.admin))
    return result
  }

  async createLendingPool(token, n) {
    await this.loadDistributor()
    const currentBlock = await this._web3.eth.getBlock('latest')
    const result = await this.distributor()
      .createLendingPool(token, currentBlock.number + n)
      .send(from(this.admin))
    return result
  }

  async openPool(id) {
    await this.loadDistributor()
    return await this.distributor().openPool(id).send(from(this.admin))
  }

  async closePool(id) {
    await this.loadDistributor()
    return await this.distributor().closePool(id).send(from(this.admin))
  }

  async createMarket(rToken, underlying, priceFeedAddr, name, symbol, anchor, startBlock) {
    return await this.orchestrator()
      .createMarket(rToken, underlying, priceFeedAddr, name, symbol, anchor, startBlock)
      .send(from(this.admin))
  }

  async setPriceFeedAddress(symbol, addr) {
    await this.loadOracle()
    return await this.oracle().setPriceFeedAddress(symbol, addr).send(from(this.admin))
  }

  async query(contract, method, ...args) {
    const loadFn = `load${this.pascalCase(contract)}`
    await this[loadFn]()
    const instance = this[`_${contract}`]
    return await instance.methods[method](...args).call()
  }

  async events(contract, event) {
    const loadFn = `load${this.pascalCase(contract)}`
    if (this[loadFn]) {
      await this[loadFn]()
    }
    const options = {
      toBlock: 'latest',
    }
    const instance = this[`_${contract}`]
    const events = await instance.getPastEvents(event, options)
    return events
  }

  pascalCase(str) {
    let result = ''
    for (let i = 0; i < str.length; i++) {
      if (i === 0) result += str[i].toUpperCase()
      else result += str[i]
    }
    return result
  }
}

async function main(argv) {
  const cmd = argv[2]
  const options = {
    Web3,
    network: RealDAO.Networks[env.current],
    provider: env.networks[env.current].provider,
    supremeAddress: env.networks[env.current].supremeAddress,
  }
  const helper = new ContractHelper(options)
  await helper.run(cmd, argv.slice(3))
  process.exit(0)
}

main(process.argv).then().catch(console.log)
