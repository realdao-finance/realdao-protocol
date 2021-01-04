pragma solidity ^0.6.0;

// The explanatory comments can be removed, but the layout specifications should be followed

//============================================================================
// Imports
// 1. Thirdparty interfaces
// 2. Internal interfaces
// 3. Thirdparty libraries
// 4. Internal libraries
// 5. internal modules
//============================================================================

//============================================================================
// Convenient interface declarations
//============================================================================

interface SimpleInterface {
  function doSomething() external returns (uint256);
}

contract Template {
  //============================================================================
  // Using statements
  //============================================================================

  // using SafeMath for uint256;

  //============================================================================
  // Type definitions
  //============================================================================

  struct SomeStruct {
    uint256 x;
    string y;
  }

  enum SomeEnum { First, Second }

  //============================================================================
  // States
  // 1. public variables
  // 2. public constants
  // 3. internal variables (without visibility modifier)
  // 4. internal constants  (without visibility modifier)
  //============================================================================

  mapping(address => uint256) public balances;
  address public admin;

  uint256 public constant maxSupply = 1e18;

  uint256 userCount;

  uint256 constant MAX_USER_COUNT = 1000;

  //============================================================================
  // Events
  //============================================================================

  event SomeEvent(uint256 arg1, address arg2);

  //============================================================================
  // Modifiers
  //============================================================================

  modifier onlyAdmin {
    require(msg.sender == admin, "Template/Permission denied");
    _;
  }

  //============================================================================
  // Initializations
  // 1. constructor
  // 2. initialize
  //============================================================================

  constructor() public {}

  function initialize() external {}

  //============================================================================
  // Transaction methods
  // 1. fallback
  // 2. receive
  // 3. payable transactions
  // 4. unpayable transactions
  //============================================================================

  fallback() external payable {}

  receive() external payable {}

  function supply() external payable {}

  function borrow() external {}

  //============================================================================
  // Querying methods
  //============================================================================

  function balanceOf(address user) external view returns (uint256) {
    return balances[user];
  }

  function add(uint256 a, uint256 b) external pure returns (uint256) {
    return a + b;
  }

  //============================================================================
  // Governance methods
  //============================================================================

  function mint(address account, uint256 amount) external onlyAdmin {}

  //============================================================================
  // Internal methods
  //============================================================================

  function mintInternal(address account, uint256 amount) internal {}
}
