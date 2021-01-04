const Web3 = require('web3')
const { advanceBlocks } = require('../test/util/advance')
const { RealDAO } = require('../sdk')
const env = require('../.env.js')

function from(account, value) {
  return { from: account, gas: 4000000, value }
}

class SmokeTest extends RealDAO {
  async run() {
    global.web3 = this._web3
    const accounts = await this._web3.eth.getAccounts()
    const ETH_PRICE = 400e8
    const admin = (this.admin = accounts[0])
    const user1 = accounts[1]
    const user2 = accounts[2]
    const user3 = accounts[3]

    await this.loadOrchestrator()
    await this.loadDistributor()
    await this.loadOracle()
    await this.loadController()
    await this.loadDOL()
    await this.loadReporter()
    await this.loadRTokens()

    const distributor = this.distributor()
    const oracle = this.oracle()
    const controller = this.controller()
    const dol = this.dol()
    const reporter = this.reporter()
    const rETH = this.rETH()
    const rDOL = this.rDOL()

    const rETHAddr = this.rETH(true).options.address
    const rDOLAddr = this.rDOL(true).options.address
    // setup contracts
    const currentBlock = await this._web3.eth.getBlock('latest')
    await distributor.createLendingPool(rETHAddr, currentBlock.number + 2).send(from(admin))
    await distributor.createLendingPool(rDOLAddr, currentBlock.number + 3).send(from(admin))
    await advanceBlocks(2)

    // setup mock data
    await oracle.setUnderlyingPrice('ETH', ETH_PRICE.toString()).send(from(admin))

    // supply ether
    await rETH.mint().send(from(user1, 10e18))
    await rETH.mint().send(from(user2, 2e18))

    // borrow dol
    await rDOL.borrow(2000e8).send(from(user1))
    await rDOL.borrow(400e8).send(from(user2))

    // transfer dol
    await dol.transfer(user3, 1000e8).send(from(user1))

    // supply dol
    await dol.approve(rDOLAddr, 500e8).send(from(user3))
    await rDOL.mint(500e8).send(from(user3))

    // borrow ether
    await rETH.borrow(String(0.5e18)).send(from(user3))

    // transfer ether
    await rETH.transfer(user3, 1e8).send(from(user1))

    // transfer rDOL'
    await dol.transfer(user3, 100e8).send(from(user2))

    // redeem ether'
    await rETH.redeem(0.5e8).send(from(user3))

    // redeem dol
    await rDOL.redeem(50e8).send(from(user3))

    // markets
    const markets = await reporter.getAllMarketInfo().call()
    console.log('markets', markets)

    // pools
    const powerRecord1 = await distributor.getAccountRecords(user1).call()
    console.log('powerRecord1', powerRecord1)

    const powerRecord2 = await distributor.getAccountRecords(user2).call()
    console.log('powerRecord2', powerRecord2)

    const powerRecord3 = await distributor.getAccountRecords(user3).call()
    console.log('powerRecord3', powerRecord3)

    const distributorStats = await distributor.getDistributorStats().call()
    console.log('distributorStats', distributorStats)

    const allPools = await distributor.getAllPools().call()
    console.log('allPools', allPools)

    // account
    const liquidity1 = await controller.getAccountLiquidity(user1).call()
    console.log(`user1: liquidity(${liquidity1[0].toString()}), shortfall(${liquidity1[1].toString()})`)

    const liquidity2 = await controller.getAccountLiquidity(user2).call()
    console.log(`user1: liquidity(${liquidity2[0].toString()}), shortfall(${liquidity2[1].toString()})`)

    const liquidity3 = await controller.getAccountLiquidity(user3).call()
    console.log(`user1: liquidity(${liquidity2[0].toString()}), shortfall(${liquidity3[1].toString()})`)

    const balances1 = await reporter.getAllRTokenBalances(user1).call()
    console.log('balances1', balances1)

    const balances2 = await reporter.getAllRTokenBalances(user2).call()
    console.log('balances2', balances2)

    const balances3 = await reporter.getAllRTokenBalances(user3).call()
    console.log('balances3', balances3)

    // prices
    const prices = await reporter.getUnderlyingPrices().call()
    console.log('prices', prices)

    return 'ok!'
  }
}

async function main(argv) {
  const options = {
    Web3,
    network: RealDAO.Networks[env.current],
    provider: env.networks[env.current].provider,
    supremeAddress: env.networks[env.current].supremeAddress,
  }
  const smoke = new SmokeTest(options)
  await smoke.run()
  process.exit(0)
}

main(process.argv).then().catch(console.log)
