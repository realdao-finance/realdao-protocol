pragma solidity ^0.6.0;

import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/PriceOracleInterface.sol";
import "./interfaces/DistributorInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./UpgradableProxy.sol";
import "./AuthBase.sol";
import "./REther.sol";
import "./RDOL.sol";
import "./RErc20.sol";

interface InitializableInterface {
  function initialize(address admin) external;
}

/**
 * @title Orchestrator contract
 */
contract Orchestrator is AuthBase {
  address public guardian;
  bool public distributorFinal = false;

  mapping(string => address) addresses;

  string constant ADDR_RDS = "RDS";
  string constant ADDR_DOL = "DOL";
  string constant ADDR_ORACLE = "ORACLE";
  string constant ADDR_INTEREST_RATE_STRATEGY = "INTEREST_RATE_STRATEGY";
  string constant ADDR_MARKET_CONTROLLER = "MARKET_CONTROLLER";
  string constant ADDR_DISTRIBUTOR = "DISTRIBUTOR";
  string constant ADDR_COUNCIL = "COUNCIL";
  string constant ADDR_DEMOCRACY = "DEMOCRACY";
  string constant ADDR_REPORTER = "REPORTER";

  uint8 constant ERR_INVALID_CONTRACT_NUMBER = 1;
  uint8 constant ERR_ONLY_GUARDIAN = 2;
  uint8 constant ERR_INIT_DEMOCRACY = 3;
  uint8 constant ERR_CHANGE_DEMOCRACY = 4;
  uint8 constant ERR_PROXY_ALREADY_CREATED = 5;
  uint8 constant ERR_PROXY_NOT_CREATED = 6;
  uint8 constant ERR_DEMOCRACY_NOT_SET = 7;
  uint8 constant ERR_DISTRIBUTOR_FINAL = 8;

  event ProxyCreated(string key, address proxy, address indexed impl);
  event ProxyUpgraded(string key, address proxy, address oldImpl, address newImpl);
  event ContractChanged(string key, address oldAddr, address newAddr);

  /**
   * @notice Initialize and setup most of the contract in realdao protocol
   * @param _controllerParts Addresses of MarketController implementation parts
   * @param _contracts Addresses of the main contracts in realdao protocol<br/>
   *        Array layout:<br/>
   *        0. MarketController<br/>
   *        1. Distributor<br/>
   *        2. Council<br/>
   *        3. InterestRateModel<br/>
   *        4. PriceOracle<br/>
   *        5. DOL<br/>
   *        6. RDS<br/>
   *        7. ProtocolReporter<br/>
   * @param _rTokenParts Address of RToken implementation parts
   * @param _rETH Address of the rETH contract
   * @param _rDOL Address of the rDOL contract
   */
  function initialize(
    address[] calldata _controllerParts,
    address[] calldata _contracts,
    address[] calldata _rTokenParts,
    address payable _rETH,
    address _rDOL
  ) external {
    guardian = msg.sender;
    address self = address(this);
    super.initialize(self);

    checkParams(_contracts.length == 8, ERR_INVALID_CONTRACT_NUMBER, "Orchestrator/invalid contract number");

    address _controller = createImplProxy(ADDR_MARKET_CONTROLLER, _contracts[0], new bytes(0));
    MarketControllerInterface controller = MarketControllerInterface(_controller);
    controller.initialize(self);
    controller.bind(_controllerParts);

    bytes memory initParams2 = abi.encodeWithSignature("initialize(address)", self);
    createImplProxy(ADDR_DISTRIBUTOR, _contracts[1], initParams2);

    setAddress(ADDR_COUNCIL, _contracts[2]);
    InitializableInterface(_contracts[2]).initialize(self);

    setAddress(ADDR_INTEREST_RATE_STRATEGY, _contracts[3]);
    InitializableInterface(_contracts[3]).initialize(self);

    setAddress(ADDR_ORACLE, _contracts[4]);
    InitializableInterface(_contracts[4]).initialize(self);

    setAddress(ADDR_DOL, _contracts[5]);

    // rds = RDS(_rds);
    setAddress(ADDR_RDS, _contracts[6]);
    // rds.initialize(address(distributor));

    setAddress(ADDR_REPORTER, _contracts[7]);
    InitializableInterface(_contracts[7]).initialize(self);

    REther rETH = REther(_rETH);
    rETH.initialize(self, _rTokenParts);

    RDOL rDOL = RDOL(_rDOL);
    rDOL.initialize(self, _contracts[5], _rTokenParts);

    controller.supportMarket(_rETH);
    controller.supportMarket(_rDOL);
  }

  /**
   * @notice Add a new market
   * @param rToken Address of the money market
   * @param priceFeed Price feed address of the asset anchored by the market
   * @param poolStartBlock Launching block of the pool
   */
  function setupMarket(
    address rToken,
    address priceFeed,
    uint256 poolStartBlock
  ) external onlyCouncil {
    MarketControllerInterface(getAddress(ADDR_MARKET_CONTROLLER)).supportMarket(rToken);
    string memory symbol = RTokenInterface(rToken).anchorSymbol();
    PriceOracleInterface(getAddress(ADDR_ORACLE)).setPriceFeedAddress(symbol, priceFeed);
    DistributorInterface(getAddress(ADDR_DISTRIBUTOR)).createLendingPool(rToken, poolStartBlock);
  }

  /**
   * @notice Get RDS address
   * @return Address of RDS contract
   */
  function getRDS() external view returns (address) {
    return getAddress(ADDR_RDS);
  }

  /**
   * @notice Get DOL address
   * @return Address of DOL contract
   */
  function getDOL() external view returns (address) {
    return getAddress(ADDR_DOL);
  }

  /**
   * @notice Get price oracle address
   * @return Address of the price oracle contract
   */
  function getOracle() external view returns (address) {
    return getAddress(ADDR_ORACLE);
  }

  /**
   * @notice Get InterestRateModel address
   * @return Address of InterestRateModel contract
   */
  function getInterestRateModel() external view returns (address) {
    return getAddress(ADDR_INTEREST_RATE_STRATEGY);
  }

  /**
   * @notice Get MarketController address
   * @return Address of MarketController proxy contract
   */
  function getMarketController() external view returns (address) {
    return getAddress(ADDR_MARKET_CONTROLLER);
  }

  /**
   * @notice Get Distributor address
   * @return Address of Distributor proxy contract
   */
  function getDistributor() external view returns (address) {
    return getAddress(ADDR_DISTRIBUTOR);
  }

  /**
   * @notice Get ProtocolReporter address
   * @return Address of ProtocolReporter contract
   */
  function getReporter() external view returns (address) {
    return getAddress(ADDR_REPORTER);
  }

  /**
   * @notice Get Council address
   * @return Address of Council contract
   */
  function getCouncil() external view returns (address) {
    return getAddress(ADDR_COUNCIL);
  }

  /**
   * @notice Get Democracy address
   * @return Address of Democracy contract
   */
  function getDemocracy() external view returns (address) {
    return getAddress(ADDR_DEMOCRACY);
  }

  /**
   * @notice Change ProtocolReporter contract
   * @param _reporter The address of the new ProtocolReporter contract
   */
  function setReporter(address _reporter) external onlyCouncil {
    setAddress(ADDR_REPORTER, _reporter);
  }

  /**
   * @notice Set the distributor contract to final
   */
  function setDistributorFinal() external onlyCouncil {
    distributorFinal = true;
  }

  /**
   * @notice Upgrade Distributor contract implementation
   * @param _distributor The address of the new Distributor contract
   */
  function upgradeDistributor(address _distributor) external onlyCouncil {
    checkBusiness(!distributorFinal, ERR_DISTRIBUTOR_FINAL, "Orchestrator/distributor is final");
    updateImpl(ADDR_DISTRIBUTOR, _distributor);
  }

  /**
   * @notice Upgrade MarketController contract implementation
   * @param _controller The address of the new MarketController contract
   */
  function upgradeMarketController(address _controller) external onlyCouncil {
    updateImpl(ADDR_MARKET_CONTROLLER, _controller);
  }

  /**
   * @notice Change the price oracle contract
   * @param _oracle The address of the new price oracle contract
   */
  function setOracle(address _oracle) external onlyCouncil {
    setAddress(ADDR_ORACLE, _oracle);
  }

  /**
   * @notice Change InterestRateModel contract
   * @param _interestRateModel The address of the new InterestRateModel contract
   */
  function setInterestRateModel(address _interestRateModel) external onlyCouncil {
    setAddress(ADDR_INTEREST_RATE_STRATEGY, _interestRateModel);
  }

  /**
   * @notice Change Council contract
   * @param _council The address of the new Council contract
   */
  function setCouncil(address _council) external onlyDemocracy {
    setAddress(ADDR_COUNCIL, _council);
  }

  /**
   * @notice Change Democracy contract
   * @param _democracy The address of the new Democracy contract
   */
  function setDemocracy(address _democracy) external {
    address current = getAddress(ADDR_DEMOCRACY);
    if (current == address(0)) {
      check(
        msg.sender == getAddress(ADDR_COUNCIL) || msg.sender == guardian,
        ERR_TYPE_AUTH,
        ERR_INIT_DEMOCRACY,
        "Orchestrator/initialize democracy requires council permission"
      );
    } else {
      check(
        msg.sender == current || msg.sender == guardian,
        ERR_TYPE_AUTH,
        ERR_CHANGE_DEMOCRACY,
        "Orchestrator/change democracy requires democracy permission"
      );
    }
    setAddress(ADDR_DEMOCRACY, _democracy);
  }

  /**
   * @notice Abdicate the guardian account
   */
  function abdicate() external onlyCouncil {
    checkBusiness(
      getAddress(ADDR_DEMOCRACY) != address(0),
      ERR_DEMOCRACY_NOT_SET,
      "Orchestrator/should set democracy before abdication"
    );
    guardian = address(0);
  }

  function getAddress(string memory key) internal view returns (address) {
    return addresses[key];
  }

  function setAddress(string memory key, address value) internal {
    address oldAddr = addresses[key];
    emit ContractChanged(key, oldAddr, value);
    addresses[key] = value;
  }

  /**
   * @dev internal function to update the implementation of a specific component of the protocol
   * @param key the key of the contract to be updated
   * @param impl the address of the new implementation
   * @param initialCall initialization calldata
   **/
  function createImplProxy(
    string memory key,
    address impl,
    bytes memory initialCall
  ) internal returns (address payable) {
    address payable proxyAddress = address(uint160(getAddress(key)));
    expect(proxyAddress == address(0), ERR_PROXY_ALREADY_CREATED, "Orchestrator/proxy already created");

    UpgradableProxy proxy = new UpgradableProxy();
    proxy.initialize(impl, initialCall);
    addresses[key] = address(proxy);
    emit ProxyCreated(key, address(proxy), impl);
    return address(proxy);
  }

  function updateImpl(string memory key, address newImpl) internal returns (address) {
    address payable proxyAddress = address(uint160(getAddress(key)));
    expect(proxyAddress != address(0), ERR_PROXY_NOT_CREATED, "Orchestrator/proxy not created");

    UpgradableProxy proxy = UpgradableProxy(proxyAddress);
    address oldImpl = proxy._implementation();
    proxy._upgrade(newImpl);
    emit ProxyUpgraded(key, address(proxy), oldImpl, newImpl);
    return proxyAddress;
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_ORCHESTRATOR;
  }
}
