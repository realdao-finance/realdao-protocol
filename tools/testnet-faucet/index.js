const Web3 = require('web3')
const fastify = require('fastify')
const path = require('path')
const { RealDAO } = require('../../sdk')
const env = require('../../.env.js')
const { advanceBlock } = require('../../test/util/advance')

function fail(reply, error) {
  reply.send({
    success: false,
    error,
  })
}

function ok(reply, result) {
  reply.send({
    success: true,
    result,
  })
}

function transferBatch(tokens, sender, recipient, amount) {
  const transactions = tokens.map((token) => {
    return token.transfer(recipient, amount).send({ from: sender, gas: 4000000 })
  })
  return Promise.all(transactions)
}

async function main(argv) {
  const addr = argv[2]
  const web3 = new Web3(env.networks[env.current].provider)
  global.web3 = web3
  const realDAO = new RealDAO({
    Web3,
    env: env.current,
    provider: env.networks[env.current].provider,
    orchestrator: env.networks[env.current].orchestrator,
  })
  await realDAO.loadDistributor()
  const pools = await realDAO.distributor().getAllPools().call()
  console.log('pools:', pools)
  let fakeLPTokens = []
  for (const pool of pools) {
    fakeLPTokens.push(realDAO.erc20Token(pool.tokenAddr))
  }
  const accounts = await web3.eth.getAccounts()
  const admin = accounts[0]
  const userStats = new Map()

  function addCount(user) {
    const current = userStats.get(user)
    if (!current) {
      userStats.set(user, 1)
    } else {
      userStats.set(user, current + 1)
    }
  }

  const server = fastify({ logger: true })
  server.register(require('fastify-cors', {}))
  server.register(require('fastify-formbody'))
  server.register(require('fastify-static'), {
    root: path.join(__dirname, 'public'),
  })

  server.get('/', function (_, reply) {
    return reply.sendFile('index.html')
  })

  server.post('/request', (request, reply) => {
    const recipient = request.body.recipient
    if (userStats.get(recipient) >= 3) {
      return fail(reply, 'Too many times')
    }
    if (!web3.utils.isAddress(recipient)) {
      return fail(reply, 'Not an address')
    }
    transferBatch(fakeLPTokens, admin, recipient, BigInt(1e21).toString())
      .then((result) => {
        addCount(recipient)
        ok(reply, result.transactionHash)
      })
      .catch((err) => {
        fail(reply, err)
      })
  })

  const port = process.env.PORT || 3000
  server.listen(port, '0.0.0.0', (err, address) => {
    if (err) throw err
  })

  setInterval(() => {
    advanceBlock()
      .then(() => {
        console.log('advance block success')
      })
      .catch((err) => {
        console.log('advance block failed:', err)
      })
  }, 15000)
}

main(process.argv).then().catch(console.log)
