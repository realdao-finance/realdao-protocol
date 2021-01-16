pragma solidity ^0.6.0;

contract FakeERC20 {
  string public name;
  string public symbol;
  uint8 public decimals;
  uint256 public totalSupply;

  mapping(address => uint256) balances;
  mapping(address => mapping(address => uint256)) allowed;

  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256 _initialIssue
  ) public {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    totalSupply = _initialIssue;
    balances[msg.sender] = _initialIssue;
    emit Transfer(address(0), msg.sender, _initialIssue);
  }

  function balanceOf(address tokenOwner) external view returns (uint256) {
    return balances[tokenOwner];
  }

  function transfer(address dst, uint256 amount) external returns (bool) {
    balances[msg.sender] = safeSub(balances[msg.sender], amount);
    balances[dst] = safeAdd(balances[dst], amount);
    emit Transfer(msg.sender, dst, amount);
    return true;
  }

  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) external returns (bool success) {
    balances[src] = safeSub(balances[src], amount);
    allowed[src][msg.sender] = safeSub(allowed[src][msg.sender], amount);
    balances[dst] = safeAdd(balances[dst], amount);
    emit Transfer(src, dst, amount);
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowed[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function allowance(address owner, address spender) external view returns (uint256) {
    return allowed[owner][spender];
  }

  function safeAdd(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "addition overflow");
    return c;
  }

  function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a, "subtraction underflow");
    return a - b;
  }
}
