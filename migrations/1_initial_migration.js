const Migrations = artifacts.require('Migrations')

async function main(deployer) {
  await deployer.deploy(Migrations)
}

module.exports = main
