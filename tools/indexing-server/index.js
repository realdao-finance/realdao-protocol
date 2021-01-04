const fastify = require('fastify')
const Service = require('./service')
const constants = require('./constants')

async function main(argv) {
  const dataDir = './.data'
  const service = new Service({ dataDir, refreshLimit: 200, staleThreshold: 300 })
  await service.initialize()
  service.start()

  const server = fastify({ logger: true })
  server.register(require('fastify-cors', {}))

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

  function parseIntOr(val, dft) {
    let n = Number.parseInt(val)
    return Number.isNaN(n) ? dft : n
  }

  function getPaginationParams(request) {
    return {
      offset: parseIntOr(request.query.offset, 0),
      limit: parseIntOr(request.query.limit, 25),
    }
  }

  server.get('/potential_liquidations', (request, reply) => {
    const { offset, limit } = getPaginationParams(request)
    service
      .getDangerousAccounts(offset, limit)
      .then((result) => {
        ok(reply, result)
      })
      .catch((err) => {
        fail(reply, err)
      })
  })

  server.get('/council_proposals', (request, reply) => {
    const { offset, limit } = getPaginationParams(request)
    let state = 0
    const stateQuery = request.query.state
    switch (stateQuery) {
      case 'all':
        state = 0
        break
      case 'pending':
        state = constants.CouncilProposalState.Pending
        break
      case 'queued':
        state = constants.CouncilProposalState.Queued
        break
      case 'executed':
        state = constants.CouncilProposalState.Executed
      default:
        break
    }
    service
      .getCouncilProposals(state, offset, limit)
      .then((result) => {
        ok(reply, result)
      })
      .catch((err) => {
        fail(reply, err)
      })
  })

  server.get('/council_proposal/:id', (request, reply) => {
    const id = Number(request.params.id)
    if (Number.isNaN(id)) {
      return fail(reply, 'Invalid proposal id')
    }
    service
      .getCouncilProposalDetail(id)
      .then((result) => {
        ok(reply, result)
      })
      .catch((err) => {
        fail(reply, err)
      })
  })

  const port = 3000
  server.listen(port, '0.0.0.0', (err, address) => {
    if (err) throw err
  })
}

main(process.argv).then().catch(console.log)
