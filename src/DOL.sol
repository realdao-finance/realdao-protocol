pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath.sol";
import "./AuthBase.sol";

/**
 * @title DOL stablecoin contract (EIP-20 compatible)
 */
contract DOL is AuthBase {
  using SafeMath for uint256;

  /// @notice EIP-20 token name for this token
  string public constant name = "DOL Stablecoin";

  /// @notice EIP-20 token symbol for this token
  string public constant symbol = "DOL";

  /// @notice EIP-20 token decimals for this token
  uint8 public constant decimals = 8;

  /// @notice Total number of tokens in circulation
  uint256 public totalSupply;

  /// @notice Allowance amounts on behalf of others
  mapping(address => mapping(address => uint256)) internal allowances;

  /// @notice Official record of token balances for each account
  mapping(address => uint256) internal balances;

  /// @notice The distributor address that have the auth to mint or burn tokens
  address public superior;

  /// @notice The standard EIP-20 transfer event
  event Transfer(address indexed from, address indexed to, uint256 amount);

  /// @notice The standard EIP-20 approval event
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  /// @notice For safety auditor: the superior should be the deployed RDOL contract address
  modifier onlySuperior {
    require(superior == msg.sender, "DOL/permission denied");
    _;
  }

  /**
   * @notice Initialize the DOL contract
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);
  }

  /**
   * @notice Set superior address
   * @param _superior The address of the superior contract
   */
  function setSuperior(address _superior) external onlyCouncil {
    superior = _superior;
  }

  /**
   * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
   * @param account The address of the account holding the funds
   * @param spender The address of the account spending the funds
   * @return The number of tokens approved
   */
  function allowance(address account, address spender) external view returns (uint256) {
    return allowances[account][spender];
  }

  /**
   * @notice Approve `spender` to transfer up to `amount` from `src`
   * @dev This will overwrite the approval amount for `spender`
   *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
   * @param spender The address of the account which may transfer tokens
   * @param amount The number of tokens that are approved (2^256-1 means infinite)
   * @return Whether or not the approval succeeded
   */
  function approve(address spender, uint256 amount) external returns (bool) {
    address owner = msg.sender;
    require(spender != address(0), "DOL/approve to zero address");
    allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
    return true;
  }

  /**
   * @notice Get the number of tokens held by the `account`
   * @param account The address of the account to get the balance of
   * @return The number of tokens held
   */
  function balanceOf(address account) external view returns (uint256) {
    return balances[account];
  }

  /**
   * @notice Transfer `amount` tokens from `msg.sender` to `dst`
   * @param dst The address of the destination account
   * @param amount The number of tokens to transfer
   * @return Whether or not the transfer succeeded
   */
  function transfer(address dst, uint256 amount) external returns (bool) {
    return transferFrom(msg.sender, dst, amount);
  }

  /**
   * @notice Transfer `amount` tokens from `src` to `dst`
   * @param src The address of the source account
   * @param dst The address of the destination account
   * @param amount The number of tokens to transfer
   * @return Whether or not the transfer succeeded
   */
  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) public returns (bool) {
    require(balances[src] >= amount, "DOL/insufficient-balance");
    require(src != address(0), "DOL/transfer from zero address");
    require(dst != address(0), "DOL/transfer to zero address");

    address sender = msg.sender;
    uint256 allowed = allowances[src][sender];
    if (sender != src && allowed != uint256(-1)) {
      require(allowed >= amount, "DOL/insufficient-allowance");
      allowances[src][sender] = allowed.sub(amount);
      emit Approval(src, sender, allowances[src][sender]);
    }
    balances[src] = balances[src].sub(amount);
    balances[dst] = balances[dst].add(amount);
    emit Transfer(src, dst, amount);
    return true;
  }

  /**
   * @notice Mint `amount` tokens for 'src'
   * @param src The address to receive the mint tokens
   * @param amount The number of tokens to mint
   */
  function mint(address src, uint256 amount) external onlySuperior {
    require(src != address(0), "DOL/mint to zero address");

    balances[src] = balances[src].add(amount);
    totalSupply = totalSupply.add(amount);
    emit Transfer(address(0), src, amount);
  }

  /**
   * @notice Burn `amount` tokens for 'src'
   * @param src The address to burn tokens
   * @param amount The number of tokens to burn
   */
  function burn(address src, uint256 amount) external {
    require(balances[src] >= amount, "DOL/insufficient-balance");
    require(src != address(0), "DOL/burn from zero address");

    address sender = msg.sender;
    uint256 allowed = allowances[src][sender];
    if (src != sender && allowed != uint256(-1)) {
      require(allowed >= amount, "DOL/insufficient-allowance");
      allowances[src][sender] = allowed.sub(amount);
      emit Approval(src, sender, allowances[src][sender]);
    }
    balances[src] = balances[src].sub(amount);
    totalSupply = totalSupply.sub(amount);
    emit Transfer(src, address(0), amount);
  }

  function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
    require(n < 2**32, errorMessage);
    return uint32(n);
  }

  function getChainId() internal pure returns (uint256) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return chainId;
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_DOL;
  }
}
