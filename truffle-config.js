const HDWalletProvider = require('truffle-hdwallet-provider')
const env = require('./.env.js')
const networks = env.networks

module.exports = {
  contracts_directory: './src',
  compilers: {
    solc: {
      version: '0.6.0',
    },
  },
  plugins: ['solidity-coverage', 'truffle-plugin-verify'],
  api_keys: {
    etherscan: env.etherscan_api_key,
  },
  networks: {
    dev: {
      host: '127.0.0.1',
      port: 8545,
      network_id: '*',
      gas: 8000000,
    },
    ropsten: {
      provider: function () {
        return new HDWalletProvider([networks.ropsten.privateKey], networks.ropsten.provider)
      },
      network_id: 3,
      gas: 8000000,
    },
    kovan: {
      provider: function () {
        return new HDWalletProvider([networks.kovan.privateKey], networks.kovan.provider)
      },
      network_id: 42,
      gas: 8000000,
    },
    live: {
      provider: function () {
        return new HDWalletProvider([networks.live.privateKey], networks.live.provider)
      },
      network_id: 1,
      gas: 8000000,
      gasPrice: networks.live.gasPrice,
    },
  },
}
