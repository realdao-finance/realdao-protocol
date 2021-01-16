const Council = artifacts.require('Council')
const Orchestrator = artifacts.require('Orchestrator')
// const Supreme = artifacts.require('Supreme')

async function main(deployer) {
  await deployer.deploy(Council)
  await deployer.deploy(Orchestrator)
  // await deployer.deploy(Supreme)
}

module.exports = main
