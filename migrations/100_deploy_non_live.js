const MockErc20 = artifacts.require('MockErc20')
const MockErc20V2 = artifacts.require('MockErc20V2')
const MockController = artifacts.require('MockController')
const MockPriceOracle = artifacts.require('MockPriceOracle')
const MockOrchestrator = artifacts.require('MockOrchestrator')

const RDOL = artifacts.require('RDOL')
const REther = artifacts.require('REther')
const RTokenPart1 = artifacts.require('RTokenPart1')
const RTokenPart2 = artifacts.require('RTokenPart2')
const RTokenPart3 = artifacts.require('RTokenPart3')
const RDS = artifacts.require('RDS')
const DOL = artifacts.require('DOL')
const Distributor = artifacts.require('Distributor')
const MarketController = artifacts.require('MarketController')
const MarketControllerPart1 = artifacts.require('MarketControllerPart1')
const InterestRateModel = artifacts.require('InterestRateModel')
const ChainlinkPriceOracle = artifacts.require('ChainlinkPriceOracle')
const ProtocolReporter = artifacts.require('ProtocolReporter')
const Democracy = artifacts.require('Democracy')
const Council = artifacts.require('Council')
const Orchestrator = artifacts.require('Orchestrator')
const Supreme = artifacts.require('Supreme')
const MockMarketControllerV2 = artifacts.require('MockMarketControllerV2')

module.exports = function (deployer, network) {
  deployer.then(async () => {
    const contracts = [
      MarketControllerPart1,
      MarketController,
      Distributor,
      RTokenPart1,
      RTokenPart2,
      RTokenPart3,
      REther,
      RDOL,
      RDS,
      DOL,
      InterestRateModel,
      ChainlinkPriceOracle,
      ProtocolReporter,
      Democracy,
      Council,
      Orchestrator,
      Supreme,
    ]
    if (network === 'dev') {
      contracts.push(MockController)
      contracts.push(MockOrchestrator)
      contracts.push(MockPriceOracle)
      contracts.push(MockMarketControllerV2)
      contracts.push(MockErc20)
    }
    for (let c of contracts) {
      await deployer.deploy(c)
    }
    await deployer.deploy(MockErc20V2, 'Uniswap V2', 'UNI-V2', 18, (10n ** 26n).toString())
    const mockLPToken = MockErc20V2.address
    await deployer.deploy(MockErc20V2, 'renBTC', 'renBTC', 8, (1e16).toString())
    const mockRenBTC = MockErc20V2.address

    console.log('Deploy unittest Done!')

    const oracleAddress = network === 'dev' ? MockPriceOracle.address : ChainklinkPriceOracle.address
    const rTokenParts = [RTokenPart1.address, RTokenPart2.address, RTokenPart3.address]
    const initParams = [
      [MarketControllerPart1.address],
      [
        MarketController.address,
        Distributor.address,
        Council.address,
        InterestRateModel.address,
        oracleAddress,
        DOL.address,
        RDS.address,
        ProtocolReporter.address,
      ],
      rTokenParts,
      REther.address,
      RDOL.address,
    ]
    console.log('====================================================')
    console.log('Contract-helper script usage:')
    const script = 'node scripts/contract-helper.js'
    console.log(`\n${script} setOrchestrator ${Orchestrator.address}`)
    console.log(`\n${script} getOrchestrator`)
    console.log(`\n${script} initializeOrchestrator '${JSON.stringify(initParams)}'`)
    console.log(`\n${script} createExchangingPool <lpToken> <n blocks>`)
    console.log(`\n${script} createLendingPool <lpToken> <n blocks>`)
    console.log(`\n${script} setPriceFeedAddress <address>`)
    console.log(`\n${script} setupMarket <rToken> <price feed>  <n blocks>`)
    console.log(`\n${script} events <contract> <event>`)
    console.log(`\n${script} query <contract> <methods> <arg1> <arg2>`)
    console.log('\n')
    const web3Cli = 'node scripts/web3-cli.js'
    console.log(`\n${web3Cli} advanceBlocks <n>`)
    console.log(`\n${web3Cli} sendETH <amount> <to>`)
    console.log('====================================================')
    console.log('Supreme address:', Supreme.address)
    console.log('Mock lpToken address:', mockLPToken)
    console.log('Mock renBTC address:', mockRenBTC)
    console.log('BTC price feed in Mainnet:\t', '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c')
    console.log('ETH price feed in Mainnet:\t', '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419')
    console.log('BTC price feed in Kovan:\t', '0x6135b13325bfC4B00278B4abC5e20bbce2D6580e')
    console.log('ETH price feed in Kovan:\t', '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419')
    console.log('====================================================')
  })
}
