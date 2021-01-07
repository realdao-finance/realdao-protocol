const Web3 = require('web3')
const { advanceBlocks } = require('../test/util/advance')
const env = require('../.env.js')

class Web3Cli {
  constructor() {
    this._web3 = new Web3(env.networks[env.current].provider)
    global.web3 = this._web3
  }
  async run(cmd, args) {
    const accounts = await web3.eth.getAccounts()
    this.admin = accounts[0]
    const func = this[cmd].bind(this)
    let result = await func(...args)
    console.log(result)
  }

  async advanceBlocks(n) {
    return await advanceBlocks(n)
  }

  async getBalance(addr) {
    const balance = await web3.eth.getBalance(addr)
    console.log(Number(balance.toString()) / 1e18)
  }

  async sendETH(amount, to) {
    const value = (BigInt(amount) * 10n ** 18n).toString()
    return await web3.eth.sendTransaction({ value, to, from: this.admin })
  }
}

async function main(argv) {
  const cmd = argv[2]
  const cli = new Web3Cli()
  await cli.run(cmd, argv.slice(3))
  process.exit(0)
}

main(process.argv).then().catch(console.log)
