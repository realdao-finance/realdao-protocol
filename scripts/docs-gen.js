const path = require('path')
const fs = require('fs')

function genDoc(contract, file) {
  const { userdoc, devdoc, contractName } = contract
  let content = `# ${contractName}\n\n`
  if (devdoc.title) {
    content += `${devdoc.title || ''}\n\n`
  }
  if (userdoc.notice) {
    content += `!!!note\n\t${userdoc.notice || ''}\n\n`
  }
  for (const signature in devdoc.methods) {
    const { notice } = userdoc.methods[signature]
    const { details, params, returns } = devdoc.methods[signature]
    content += `## ${signature}\n\n`
    if (notice) {
      content += `${notice}\n\n`
    }
    if (details) {
      content += `!!!note\n\t${details || ''}\n\n`
    }
    if (params) {
      content += `### Params\n\n`
      content += '|||\n'
      content += '|---|---|\n'
      for (const key in params) {
        content += `|${key}|${params[key]}|\n`
      }
      content += '\n'
    }
    if (returns) {
      content += `### Returns\n\n`
      for (const key in returns) {
        content += `- ${returns[key]}\n`
      }
      content += '\n---\n'
    }
  }
  fs.writeFileSync(file, content, 'utf8')
}

function main(argv) {
  const contracts = [
    'MarketController',
    'Distributor',
    'RDS',
    'DOL',
    'REther',
    'RErc20',
    'RDOL',
    'Orchestrator',
    'Supreme',
    'ProtocolReporter',
    'Council',
    'Democracy',
    'InterestRateModel',
    'ChainlinkPriceOracle',
  ]
  const inputDir = `../build/contracts`
  const outputDir = argv[2]
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir)
  }
  for (const name of contracts) {
    const contract = require(path.join(inputDir, name + '.json'))
    const outputFile = path.join(outputDir, `${name}.md`)
    genDoc(contract, outputFile)
  }
}

main(process.argv)
