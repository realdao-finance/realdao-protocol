const Migrations = artifacts.require('Migrations')

async function main(deployer, network, accounts) {
  console.log('network:', network)
  console.log('accounts:', accounts)
  await deployer.deploy(Migrations)
}

module.exports = main
