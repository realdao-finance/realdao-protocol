// Generate by [js2dts@0.3.3](https://github.com/whxaxes/js2dts#readme)

export class RealDAO {
  Web3: any;
  constructor(options: any);
  setProvider(provider: any): void;
  chainId(): any;
  isTransactionConfirmed(hash: any): Promise<boolean>;
  loadDOL(): Promise<void>;
  loadRDS(): Promise<void>;
  loadReporter(): Promise<void>;
  loadController(): Promise<void>;
  loadDistributor(): Promise<void>;
  loadOracle(): Promise<void>;
  loadInterestRateModel(): Promise<void>;
  loadCouncil(): Promise<void>;
  loadDemocracy(): Promise<void>;
  loadRTokens(): Promise<void>;
  supreme(raw: any): any;
  orchestrator(raw: any): any;
  dol(raw: any): any;
  rds(raw: any): any;
  reporter(raw: any): any;
  controller(raw: any): any;
  distributor(raw: any): any;
  oracle(raw: any): any;
  rETH(raw: any): any;
  rDOL(raw: any): any;
  interestRateModel(raw: any): any;
  council(raw: any): any;
  democracy(raw: any): any;
  rToken(underlyingSymbol: any, raw: any): any;
  erc20Token(addr: any, raw: any): Promise<any>;
  uniswapPairView(addr: any, raw: any): any;
}
