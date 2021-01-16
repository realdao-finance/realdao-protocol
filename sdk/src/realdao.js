const ABI_Orchestrator = require('../abis/Orchestrator.json')
const ABI_ProtocolReporter = require('../abis/ProtocolReporter.json')
const ABI_MarketController = require('../abis/MarketController.json')
const ABI_Distributor = require('../abis/Distributor.json')
const ABI_DOL = require('../abis/DOL.json')
const ABI_RDS = require('../abis/RDS.json')
const ABI_REther = require('../abis/REther.json')
const ABI_RERC20 = require('../abis/RERC20.json')
const ABI_RDOL = require('../abis/RDOL.json')
const ABI_Oracle = require('../abis/PriceOracleInterface.json')
const ABI_EIP20Interface = require('../abis/EIP20Interface.json')
const ABI_InterestRateModel = require('../abis/InterestRateModel.json')
const ABI_Council = require('../abis/Council.json')
const ABI_Democracy = require('../abis/Democracy.json')

const Networks = require('./networks')

class RealDAO {
  constructor(options) {
    if (!options.Web3) throw new Error('Web3 required')

    this.Web3 = options.Web3
    this._env = options.env || 'mainnet'
    this._network = Networks[this._env]
    if (!this._network) throw new Error('Invalid env')

    this._orchestratorAddress = options.orchestrator || this._network.orchestrator

    this.setProvider(options.provider || this._network.provider)
  }

  setProvider(provider) {
    if (!provider) throw new Error('Invalid provider')

    this.provider = provider
    this._web3 = new this.Web3(this.provider)
    this._orchestrator = this._createContractInstance(ABI_Orchestrator, this._orchestratorAddress)
    this._dol = null
    this._rds = null
    this._reporter = null
    this._controller = null
    this._distributor = null
    this._rETH = null
    this._rDOL = null
    this._interestRateModel = null
    this._council = null
    this._democracy = null
    this._rTokens = {}
    this._erc20Tokens = {}
  }

  chainId() {
    return this._network.chainId
  }

  async isTransactionConfirmed(hash) {
    const tx = await this._web3.eth.getTransaction(hash)
    return !!tx && !!tx.blockHash
  }

  async loadDOL() {
    if (!this._dol) this._dol = await this._createProtocolContractInstance(ABI_DOL, 'DOL')
  }

  async loadRDS() {
    if (!this._rds) this._rds = await this._createProtocolContractInstance(ABI_RDS, 'RDS')
  }

  async loadReporter() {
    if (!this._reporter) this._reporter = await this._createProtocolContractInstance(ABI_ProtocolReporter, 'REPORTER')
  }

  async loadController() {
    if (!this._controller) {
      this._controller = await this._createProtocolContractInstance(ABI_MarketController, 'MARKET_CONTROLLER')
    }
  }

  async loadDistributor() {
    if (!this._distributor) {
      this._distributor = await this._createProtocolContractInstance(ABI_Distributor, 'DISTRIBUTOR')
    }
  }

  async loadOracle() {
    if (!this._oracle) {
      this._oracle = await this._createProtocolContractInstance(ABI_Oracle, 'ORACLE')
    }
  }

  async loadInterestRateModel() {
    if (!this._interestRateModel) {
      this._interestRateModel = await this._createProtocolContractInstance(ABI_InterestRateModel, 'INTEREST_RATE_MODEL')
    }
  }

  async loadCouncil() {
    if (!this._council) {
      this._council = await this._createProtocolContractInstance(ABI_Council, 'COUNIL')
    }
  }

  async loadDemocracy() {
    if (!this._democracy) {
      this._democracy = await this._createProtocolContractInstance(ABI_Democracy, 'DEMOCRACY')
    }
  }

  async loadRTokens() {
    await this.loadReporter()
    const reporter = this.reporter()
    const markets = await reporter.getAllMarketInfo().call()
    for (const market of markets) {
      if (market.underlyingSymbol === 'ETH') {
        this._rETH = this._createContractInstance(ABI_REther, market.rToken)
        this._rTokens[market.underlyingSymbol] = this._rETH
      } else if (market.underlyingSymbol === 'DOL') {
        this._rDOL = this._createContractInstance(ABI_RDOL, market.rToken)
        this._rTokens[market.underlyingSymbol] = this._rDOL
      } else {
        const instance = this._createContractInstance(ABI_RERC20, market.rToken)
        this._rTokens[market.underlyingSymbol] = instance
      }
    }
  }

  supreme(raw) {
    return raw ? this._supreme : this._supreme.methods
  }

  orchestrator(raw) {
    if (!this._orchestrator) throw new Error('Orchestrator not loaded')
    return raw ? this._orchestrator : this._orchestrator.methods
  }

  dol(raw) {
    if (!this._dol) throw new Error('DOL not loaded')
    return raw ? this._dol : this._dol.methods
  }

  rds(raw) {
    if (!this._rds) throw new Error('RDS not loaded')
    return raw ? this._rds : this._rds.methods
  }

  reporter(raw) {
    if (!this._reporter) throw new Error('Reporter not loaded')
    return raw ? this._reporter : this._reporter.methods
  }

  controller(raw) {
    if (!this._controller) throw new Error('Controller not loaded')
    return raw ? this._controller : this._controller.methods
  }

  distributor(raw) {
    if (!this._distributor) throw new Error('Distributor not loaded')
    return raw ? this._distributor : this._distributor.methods
  }

  oracle(raw) {
    if (!this._oracle) throw new Error('Oracle not loaded')
    return raw ? this._oracle : this._oracle.methods
  }

  rETH(raw) {
    if (!this._rETH) throw new Error('REther not loaded')
    return raw ? this._rETH : this._rETH.methods
  }

  rDOL(raw) {
    if (!this._rDOL) throw new Error('RDOL not loaded')
    return raw ? this._rDOL : this._rDOL.methods
  }

  interestRateModel(raw) {
    if (!this._interestRateModel) throw new Error('InterestRateModel not loaded')
    return raw ? this._interestRateModel : this._interestRateModel.methods
  }

  council(raw) {
    if (!this._council) throw new Error('Council not loaded')
    return raw ? this._council : this._council.methods
  }

  democracy(raw) {
    if (!this._democracy) throw new Error('Democracy not loaded')
    return raw ? this._democracy : this._democracy.methods
  }

  rToken(underlyingSymbol, raw) {
    if (!this._rTokens[underlyingSymbol]) throw new Error('RTokens not loaded')
    return raw ? this._rTokens[underlyingSymbol] : this._rTokens[underlyingSymbol].methods
  }

  getERC20Token(addr, raw) {
    if (!this._erc20Tokens[addr]) {
      this._erc20Tokens[addr] = this._createContractInstance(ABI_EIP20Interface, addr)
    }
    return raw ? this._erc20Tokens[addr] : this._erc20Tokens[addr].methods
  }

  async _createProtocolContractInstance(abi, key) {
    const addr = await this._orchestrator.methods.getAddress(key).call()
    return new this._web3.eth.Contract(abi, addr)
  }

  _createContractInstance(abi, addr) {
    return new this._web3.eth.Contract(abi, addr)
  }
}

RealDAO.Networks = Networks
module.exports = RealDAO
