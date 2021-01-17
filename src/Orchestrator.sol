pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./interfaces/MarketControllerInterface.sol";
import "./interfaces/PriceOracleInterface.sol";
import "./interfaces/DistributorInterface.sol";
import "./interfaces/RTokenInterface.sol";
import "./libraries/Strings.sol";
import "./UpgradableProxy.sol";
import "./ErrorBase.sol";
import "./REther.sol";
import "./RDOL.sol";
import "./RERC20.sol";

interface InitializableInterface {
  function initialize(address admin) external;
}

/**
 * @title Orchestrator contract
 */
contract Orchestrator is ErrorBase {
  address public guardian;

  enum ContractVariability { None, Immutable, Replaceable, Upgradeable }

  enum UpdatePermission { None, Council, Democracy }

  struct ContractConfig {
    address addr;
    ContractVariability variability;
    UpdatePermission permission;
  }

  mapping(string => ContractConfig) contracts;

  string constant KEY_RDS = "RDS";
  string constant KEY_DOL = "DOL";
  string constant KEY_ORACLE = "ORACLE";
  string constant KEY_INTEREST_RATE_MODEL = "INTEREST_RATE_MODEL";
  string constant KEY_MARKET_CONTROLLER = "MARKET_CONTROLLER";
  string constant KEY_DISTRIBUTOR = "DISTRIBUTOR";
  string constant KEY_COUNCIL = "COUNCIL";
  string constant KEY_DEMOCRACY = "DEMOCRACY";
  string constant KEY_REPORTER = "REPORTER";

  uint8 constant ERR_INVALID_CONTRACT_NUMBER = 1;
  uint8 constant ERR_DEMOCRACY_NOT_SET = 2;
  uint8 constant ERR_CONTRACT_REGISTERED = 3;
  uint8 constant ERR_INVALID_DEMOCRACY_CONFIG = 4;
  uint8 constant ERR_CONTRACT_NOT_REGISTERED = 5;
  uint8 constant ERR_UPDATE_UNREPLACEABLE_CONTRACT = 6;
  uint8 constant ERR_REQUIRE_COUNCIL_PERMISSION = 7;
  uint8 constant ERR_REQUIRE_DEMOCRACY_PERMISSION = 8;
  uint8 constant ERR_DEMOCRACY_SHOULD_NOT_BE_PROXY = 9;

  event ProxyCreated(string key, address proxy, address indexed impl);
  event ProxyUpgraded(string key, address proxy, address oldImpl, address newImpl);
  event ContractChanged(string key, address oldAddr, address newAddr);

  /**
   * @notice Initialize and setup most of the contract in realdao protocol
   * @param _contracts Addresses of the main contracts in realdao protocol<br/>
   *        Array layout:<br/>
   *        0. MarketControllerLibrary<br/>
   *        1. MarketController<br/>
   *        2. Distributor<br/>
   *        3. InterestRateModel<br/>
   *        4. PriceOracle<br/>
   *        5. RDS<br/>
   *        6. DOL<br/>
   *        7. Council<br/>
   *        8. ProtocolReporter<br/>
   */
  function initialize(address[] calldata _contracts) external {
    guardian = msg.sender;
    address self = address(this);

    checkParams(_contracts.length == 9, ERR_INVALID_CONTRACT_NUMBER, "Orchestrator/invalid contract number");

    address controllerAddress = registerProxy(
      KEY_MARKET_CONTROLLER,
      _contracts[1],
      new bytes(0),
      UpdatePermission.Council
    );
    MarketControllerInterface controller = MarketControllerInterface(controllerAddress);
    controller.initialize(self);
    controller.bind(_contracts[0]);

    bytes memory initParams = abi.encodeWithSignature("initialize(address)", self);
    registerProxy(KEY_DISTRIBUTOR, _contracts[2], initParams, UpdatePermission.Council);

    registerContract(KEY_INTEREST_RATE_MODEL, _contracts[3], ContractVariability.Replaceable, UpdatePermission.Council);
    InitializableInterface(_contracts[3]).initialize(self);

    registerContract(KEY_ORACLE, _contracts[4], ContractVariability.Replaceable, UpdatePermission.Council);
    InitializableInterface(_contracts[4]).initialize(self);

    registerContract(KEY_RDS, _contracts[5], ContractVariability.Immutable, UpdatePermission.Council);
    InitializableInterface(_contracts[5]).initialize(self);

    registerContract(KEY_DOL, _contracts[6], ContractVariability.Immutable, UpdatePermission.Council);
    InitializableInterface(_contracts[6]).initialize(self);

    registerContract(KEY_COUNCIL, _contracts[7], ContractVariability.Replaceable, UpdatePermission.Council);
    InitializableInterface(_contracts[7]).initialize(self);

    registerContract(KEY_REPORTER, _contracts[8], ContractVariability.Replaceable, UpdatePermission.Council);
    InitializableInterface(_contracts[8]).initialize(self);
  }

  /**
   * @notice Get registered contract address
   * @param key The key of the contract
   */
  function getAddress(string memory key) public view returns (address) {
    return contracts[key].addr;
  }

  /**
   * @notice Get registered contract config
   * @param key The key of the contract
   */
  function getContractConfig(string memory key) public view returns (ContractConfig memory) {
    return contracts[key];
  }

  /**
   * @notice Register a contract
   * @param key The key of the contract
   * @param addr The address of the contract
   * @param variability The variability of the contract
   * @param permission The permission of the contract
   */
  function registerContract(
    string memory key,
    address addr,
    ContractVariability variability,
    UpdatePermission permission
  ) public {
    checkPermission(msg.sender, UpdatePermission.Council);
    checkBusiness(
      contracts[key].addr == address(0),
      ERR_CONTRACT_REGISTERED,
      "Orchestrator/contract already registered"
    );
    if (Strings.equals(key, KEY_DEMOCRACY)) {
      checkParams(
        variability == ContractVariability.Replaceable && permission == UpdatePermission.Democracy,
        ERR_INVALID_DEMOCRACY_CONFIG,
        "Orchestrator/Invalid democracy config"
      );
    }
    contracts[key] = ContractConfig({ addr: addr, variability: variability, permission: permission });
    emit ContractChanged(key, address(0), addr);
  }

  function updateContract(string memory key, address newAddr) public {
    checkBusiness(
      contracts[key].addr != address(0),
      ERR_CONTRACT_NOT_REGISTERED,
      "Orchestrator/Contract not registered"
    );
    ContractConfig storage config = contracts[key];
    checkBusiness(
      config.variability == ContractVariability.Replaceable,
      ERR_UPDATE_UNREPLACEABLE_CONTRACT,
      "Orchestrator/should not update unreplaceable contract"
    );
    checkPermission(msg.sender, config.permission);
    emit ContractChanged(key, config.addr, newAddr);
    config.addr = newAddr;
  }

  /**
   * @notice Register a proxied contract
   * @param key The key of the contract to be updated
   * @param impl The address of the contract implementation
   * @param initialCall Initialization calldata
   * @param permission The permission to upgrade to the proxy
   * @return proxy address
   **/
  function registerProxy(
    string memory key,
    address impl,
    bytes memory initialCall,
    UpdatePermission permission
  ) public returns (address) {
    checkPermission(msg.sender, UpdatePermission.Council);
    checkBusiness(
      !Strings.equals(key, KEY_DEMOCRACY),
      ERR_DEMOCRACY_SHOULD_NOT_BE_PROXY,
      "Orchestrator/democracy should not be registered as proxy"
    );
    checkBusiness(
      contracts[key].addr == address(0),
      ERR_CONTRACT_REGISTERED,
      "Orchestrator/contract already registered"
    );

    UpgradableProxy proxy = new UpgradableProxy();
    proxy.initialize(impl, initialCall);
    address proxyAddress = address(proxy);
    contracts[key] = ContractConfig({
      addr: proxyAddress,
      variability: ContractVariability.Upgradeable,
      permission: permission
    });
    emit ProxyCreated(key, proxyAddress, impl);
    return proxyAddress;
  }

  /**
   * @notice Upgrade contract implementation
   * @param key The address of the new Distributor contract
   */
  function upgradeProxy(string memory key, address newImpl) public {
    checkBusiness(
      contracts[key].addr != address(0),
      ERR_CONTRACT_NOT_REGISTERED,
      "Orchestrator/Contract not registered"
    );
    ContractConfig memory config = contracts[key];
    checkPermission(msg.sender, config.permission);

    address payable proxyAddress = address(uint160(config.addr));

    UpgradableProxy proxy = UpgradableProxy(proxyAddress);
    address oldImpl = proxy._implementation();
    proxy._upgrade(newImpl);
    emit ProxyUpgraded(key, address(proxy), oldImpl, newImpl);
  }

  /**
   * @notice Abdicate the guardian account
   */
  function abdicate() external {
    checkPermission(msg.sender, UpdatePermission.Council);
    checkBusiness(
      getAddress(KEY_DEMOCRACY) != address(0),
      ERR_DEMOCRACY_NOT_SET,
      "Orchestrator/should register democracy before abdication"
    );
    guardian = address(0);
  }

  function checkPermission(address sender, UpdatePermission permission) internal view {
    if (permission == UpdatePermission.Council) {
      check(
        sender == contracts[KEY_COUNCIL].addr || sender == guardian,
        ERR_TYPE_AUTH,
        ERR_REQUIRE_COUNCIL_PERMISSION,
        "Orchestrator/requires council permission"
      );
    } else if (permission == UpdatePermission.Democracy) {
      check(
        sender == contracts[KEY_DEMOCRACY].addr || sender == guardian,
        ERR_TYPE_AUTH,
        ERR_REQUIRE_DEMOCRACY_PERMISSION,
        "Orchestrator/requires democracy permission"
      );
    } else {
      assert(false);
    }
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_ORCHESTRATOR;
  }
}
