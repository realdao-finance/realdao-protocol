const FeedPriceOracle = artifacts.require('FeedPriceOracle')

function unuse() {}

async function main(deployer, network, accounts) {
  if (network === 'unittest') return

  unuse(deployer)

  if (network !== 'mainnet') {
    const admin = accounts[0]
    const oracleInstance = await FeedPriceOracle.deployed()
    const symbols = ['HBTC', 'HETH', 'WHT', 'ETH']
    const prices = [30000e8, 1000e8, 30e8, 1000e8]
    await oracleInstance.setUnderlyingPrices(symbols, prices, { from: admin })
  }
}

module.exports = main
