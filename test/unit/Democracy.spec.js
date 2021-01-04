const { expectSuccess } = require('../util/expect')
const Democracy = artifacts.require('Democracy')
const Council = artifacts.require('Council')

let democracy
let council
let accounts

async function deployContracts() {
  accounts = await web3.eth.getAccounts()
  democracy = await Democracy.deployed()
  council = await Council.deployed()
}

contract('Democracy:execute', () => {
  before('deply Democracy', deployContracts)

  it('should success to call self', async () => {})

  it('should success to call self with params', async () => {})
})
