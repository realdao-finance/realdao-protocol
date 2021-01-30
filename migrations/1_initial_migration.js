const Migrations = artifacts.require('Migrations')
const Web3 = require('web3')
const env = require('../.env.js')

async function main(deployer, network) {
  if (network === 'dev') {
    const web3 = new Web3(env.networks.dev.provider)
    const genesisAccounts = await web3.eth.getAccounts()
    const account = web3.eth.accounts.wallet.add(env.privateKey)
    const admin = account.address
    const amount = 50
    const value = (BigInt(amount) * 10n ** 18n).toString()
    await web3.eth.sendTransaction({ value, to: admin, from: genesisAccounts[0] })
  }
  await deployer.deploy(Migrations)
}

module.exports = main
