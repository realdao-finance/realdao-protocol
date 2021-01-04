const ABI_EIP20 = require('./EIP20Interface.json')
const Web3 = require('web3')
const fastify = require('fastify')
const path = require('path')
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

async function main(argv) {
  const addr = argv[2]
  const web3 = new Web3(env.networks[env.current].provider)
  global.web3 = web3
  const token = new web3.eth.Contract(ABI_EIP20, addr)
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
    token.methods
      .transfer(recipient, '1000000000000000000')
      .send({ from: admin, gas: 4000000 })
      .then((result) => {
        addCount(recipient)
        ok(reply, result.transactionHash)
      })
      .catch((err) => {
        fail(reply, err)
      })
  })

  const port = 3000
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
