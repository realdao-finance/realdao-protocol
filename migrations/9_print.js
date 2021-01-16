const Orchestrator = artifacts.require('Orchestrator')

function unuse() {}

async function main(deployer, network, accounts) {
  unuse(deployer)
  console.log('network:', network)
  console.log('accounts:', accounts)
  console.log('Orchestrator address:', Orchestrator.address)
}

module.exports = main
