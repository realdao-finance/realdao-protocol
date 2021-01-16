module.exports = {
  dev: {
    provider: 'ws://localhost:8545',
    chainId: 0x539,
    orchestrator: '0xfe57175001DAA3BacB220dBe30036241E20F1FA0',
  },
  test: {
    provider: 'ws://139.180.193.123:8545',
    chainId: 0x539,
    orchestrator: '0x1d736CBAB67422a524E6923A2e4f47C2Ae891335',
  },
  kovan: {
    provider: 'https://kovan.infura.io/v3/d3f8f9c2141b4561b6c7f23a34466d7c',
    chainId: 42,
    orchestrator: '0x297344B27D52abAe0f30AFE947ddAd60d425F40d',
  },
  ropsten: {
    provider: 'https://ropsten.infura.io/v3/d3f8f9c2141b4561b6c7f23a34466d7c',
    chainId: 3,
    orchestrator: '0x297344B27D52abAe0f30AFE947ddAd60d425F40d',
  },
  live: {
    provider: 'ws://localhost:8545',
    chainId: 1,
    orchestrator: '0x297344B27D52abAe0f30AFE947ddAd60d425F40d',
  },
}
