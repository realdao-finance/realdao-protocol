const { expectSuccess } = require('../util/expect')
const InterestRateModel = artifacts.require('InterestRateModel')
const MockOrchestrator = artifacts.require('MockOrchestrator')

const BLOCKS_PER_YEAR = 2102400 * 5

let accounts
let irs

async function initializeContracts() {
  accounts = await web3.eth.getAccounts()
  irs = await InterestRateModel.deployed()

  const orchestrator = await MockOrchestrator.deployed()
  await irs.initialize(orchestrator.address)
}

contract('InterestRateModel', () => {
  before('deply contracts', initializeContracts)

  it('print rates', async () => {
    const total = 10000
    for (let i = 200; i < 10000; i += 200) {
      const cash = (total - i) * 1e8
      const borrows = i * 1e8
      const reserves = 0
      const ur = await irs.utilizationRate(cash, borrows, reserves)
      const br = await irs.getBorrowRate(cash, borrows, reserves)
      const sr = await irs.getSupplyRate(cash, borrows, reserves, (1e17).toString())
      const urLiteral = Number(ur.toString()) / 1e18
      const brLiteral = (Number(br.toString()) * BLOCKS_PER_YEAR) / 1e18
      const srLiteral = (Number(sr.toString()) * BLOCKS_PER_YEAR) / 1e18
      console.log(urLiteral.toPrecision(2), brLiteral.toPrecision(2), srLiteral.toPrecision(2))
    }
  })
})
