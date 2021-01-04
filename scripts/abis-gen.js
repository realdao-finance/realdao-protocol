const path = require('path')
const fs = require('fs')

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
    'EIP20Interface',
    'Council',
    'Democracy',
    'InterestRateModel',
    'PriceOracleInterface',
  ]
  const inputDir = `../build/contracts`
  const outputDir = argv[2]
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir)
  }
  const format = argv[3] || 'json'
  for (const name of contracts) {
    const instance = require(path.join(inputDir, name + '.json'))
    let outputFile
    let content
    if (format === 'json') {
      content = JSON.stringify(instance.abi, null, 2)
      outputFile = path.join(outputDir, `${name}.json`)
    } else if (format === 'browser') {
      content = `window.ABI_${name} = ${JSON.stringify(instance.abi, null, 2)}`
      outputFile = path.join(outputDir, `${name}.js`)
    } else if (format === 'es6') {
      content = `export const ABI_${name} = ${JSON.stringify(instance.abi, null, 2)}`
      outputFile = path.join(outputDir, `${name}.js`)
    } else {
      throw new Error('Unsupported format')
    }
    fs.writeFileSync(outputFile, content, 'utf8')
  }
}

main(process.argv)
