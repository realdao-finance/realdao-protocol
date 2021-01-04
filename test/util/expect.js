const BlockchainCaller = require('./blockchain-caller')
const chain = new BlockchainCaller(web3)

async function expectRevert(transaction) {
  expect(await chain.isEthException(transaction)).to.be.true
}

async function expectFail(transaction, err1, err2) {
  const result = await transaction
  let failed = false
  for (const log of result.logs) {
    if (log.event === 'Failure') {
      if (err1) assert.equal(err1, log[0].toNumber())
      if (err2) assert.equal(err2, log[1].toNumber())
      failed = true
      break
    }
  }
  assert.equal(failed, true)
}

async function expectSuccess(transaction) {
  const result = await transaction
  let failInfo = ''
  for (const log of result.logs) {
    if (log.event === 'Failure') {
      failInfo = `err: ${log.args[0]}, info: ${log.args[1]}, detail: ${log.args[2]}`
      break
    }
  }
  assert.equal(failInfo, '')
}

function expectSimpleObjectEqual(o1, o2) {
  for (let key of Object.keys(o2)) {
    assert.equal(o1[key], o2[key])
  }
}

module.exports = {
  expectRevert,
  expectFail,
  expectSuccess,
  expectSimpleObjectEqual,
}
