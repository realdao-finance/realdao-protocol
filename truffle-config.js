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
    unittest: {
      host: '127.0.0.1',
      port: 8545,
      network_id: '*',
      gas: 8000000,
    },
    dev: {
      host: '127.0.0.1',
      port: 8545,
      network_id: '*',
      gas: 8000000,
    },
    ropsten: {
      provider: function () {
        return new HDWalletProvider([env.privateKey], networks.ropsten.provider)
      },
      network_id: 3,
      gas: 8000000,
    },
    kovan: {
      provider: function () {
        return new HDWalletProvider([env.privateKey], networks.kovan.provider)
      },
      network_id: 42,
      gas: 8000000,
    },
    testnet: {
      provider: function () {
        return new HDWalletProvider([env.privateKey], networks.testnet.provider)
      },
      network_id: 256,
      gas: 8000000,
      networkCheckTimeout: 10000,
    },
    mainnet: {
      provider: function () {
        return new HDWalletProvider([env.privateKey], networks.mainnet.provider)
      },
      network_id: 128,
      gas: 8000000,
      gasPrice: env.gasPrice,
      networkCheckTimeout: 10000,
    },
  },
}
