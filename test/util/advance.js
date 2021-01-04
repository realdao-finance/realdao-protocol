const advanceTimeAndBlock = async (time) => {
  await advanceTime(time)
  await advanceBlock()

  return Promise.resolve(web3.eth.getBlock('latest'))
}

const advanceTime = (time) => {
  return new Promise((resolve, reject) => {
    web3.eth.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_increaseTime',
        params: [time],
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err)
        }
        return resolve(result)
      }
    )
  })
}

const advanceBlock = () => {
  return new Promise((resolve, reject) => {
    web3.eth.currentProvider.send(
      {
        jsonrpc: '2.0',
        method: 'evm_mine',
        id: new Date().getTime(),
      },
      (err, result) => {
        if (err) {
          return reject(err)
        }
        return resolve(web3.eth.getBlock('latest'))
      }
    )
  })
}

async function advanceBlocks(n) {
  for (let i = 0; i < n; i++) {
    await advanceBlock()
  }
  return await web3.eth.getBlock('latest')
}

module.exports = {
  advanceTime,
  advanceBlock,
  advanceTimeAndBlock,
  advanceBlocks,
}
