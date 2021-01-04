pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./interfaces/EIP20NonStandardInterface.sol";
import "./interfaces/OrchestratorInterface.sol";
import "./libraries/SafeMath.sol";
import "./RDS.sol";
import "./AuthBase.sol";

interface Controller {
  function isListedMarket(address rToken) external returns (bool);
}

/**
 * @title Distributor contract
 * @notice Implement the distribution algorithms for the incentive token
 */
contract Distributor is AuthBase {
  using SafeMath for uint256;

  struct AccountRecord {
    uint256 power;
    uint256 mask;
    uint256 settled;
    uint256 claimed;
  }

  struct Pool {
    uint32 id;
    uint32 ptype;
    address tokenAddr;
    uint32 state;
    uint256 rewardIndex;
    uint256 lastBlockNumber;
    int256 accumulatedPower;
    uint256 accumulatedTokens;
    uint256 totalPower;
    uint256 startBlock;
  }

  struct DistributorStats {
    uint256 rewardsPerBlock;
    uint256 mineStartBlock;
    uint256 nextHalvingBlock;
    uint32 activePools;
    uint32 totalPools;
  }

  uint256 public rewardsPerBlock;
  uint256 public mineStartBlock;
  uint256 public nextHalvingBlock;

  uint32 public activePools = 0;

  Pool[] pools;
  mapping(uint32 => mapping(address => AccountRecord)) accountRecords;
  mapping(address => uint32) tokenToPoolSeq;

  int32 constant MAIN_POOL_ID = -1;
  uint256 constant BLOCKS_PER_YEAR = 2102400;
  uint256 constant MANTISSA = 1e18;

  uint32 constant POOL_STATE_NOT_START = 0;
  uint32 constant POOL_STATE_ACTIVE = 1;
  uint32 constant POOL_STATE_CLOSED = 2;

  uint32 constant POOL_TYPE_LENDING = 1;
  uint32 constant POOL_TYPE_EXCHANGING = 2;

  uint8 constant ERR_MARKET_NOT_LISTED = 1;
  uint8 constant ERR_POOL_ID_OUTOF_RANGE = 2;
  uint8 constant ERR_POOL_NOT_CREATED = 3;
  uint8 constant ERR_UNEXPECTED_POOL_ID = 4;
  uint8 constant ERR_POOL_IS_CLOSED = 5;
  uint8 constant ERR_AMOUNT_ZERO = 6;
  uint8 constant ERR_POOL_NOT_STARTED = 7;
  uint8 constant ERR_START_BLOCK_SMALL = 8;
  uint8 constant ERR_POOL_ALREADY_CREATED = 9;
  uint8 constant ERR_POOL_ALREADY_STARTED = 10;
  uint8 constant ERR_TRANSFER_IN_FAILED = 11;
  uint8 constant ERR_TRANSFER_IN_OVERFLOW = 12;
  uint8 constant ERR_TRANSFER_OUT_FAILED = 13;
  uint8 constant ERR_OPEN_TIME_NOT_UP = 14;
  uint8 constant ERR_TOTAL_POWER_CALC = 15;
  uint8 constant ERR_ACCUMULATED_POWER_CALC = 16;
  uint8 constant ERR_UPDATE_POWER_OVERFLOW = 17;
  uint8 constant ERR_POOL_NOT_ACTIVE = 18;
  uint8 constant ERR_ONLY_CONTROLLER = 19;
  uint8 constant ERR_CLOSE_LENDING_POOL_DIRECTLY = 20;

  event PoolCreated(uint256 id, uint32 ptype, uint256 startBlock);
  event PoolClosed(uint256 id);
  event MinerClaimed(address miner, uint256 id, uint256 amount);
  event MinerExited(address miner, uint256 id, uint256 amount);

  modifier onlyListedMarket {
    Controller controller = Controller(orchestrator.getMarketController());
    checkBusiness(controller.isListedMarket(msg.sender), ERR_MARKET_NOT_LISTED, "Distributor/market is not listed");
    _;
  }

  /**
   * @notice Initialize the distributor
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);

    rewardsPerBlock = 0;
    mineStartBlock = 0;
    nextHalvingBlock = 0;
  }

  //============================================================================
  // Transaction methods
  //============================================================================

  /**
   * @notice Open a pool by `id`
   * @param id Id of the pool to open
   */
  function openPool(uint32 id) external {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");
    tryOpenPool(pools[id]);
  }

  /**
   * @notice Update the latest lending `power` for the`account`
   * @param account Address of the account to be updated
   * @param power The new power of the account
   */
  function updateLendingPower(address account, uint256 power) external onlyListedMarket {
    checkBusiness(tokenToPoolSeq[msg.sender] > 0, ERR_POOL_NOT_CREATED, "Distributor/pool not created");

    uint32 id = tokenToPoolSeq[msg.sender] - 1;
    expect(id < pools.length, ERR_UNEXPECTED_POOL_ID, "Distributor/unexpected pool id");

    Pool storage pool = pools[id];
    checkBusiness(pool.state != POOL_STATE_CLOSED, ERR_POOL_IS_CLOSED, "Distributor/pool is closed");

    if (pool.state == POOL_STATE_NOT_START) {
      tryOpenPool(pool);
    }

    updatePower(pool, account, power);
  }

  /**
   * @notice Lock LP tokens to mint RDS in the exchanging pool
   * @param id Id of the pool to mint
   * @param amount The amount of the LP tokens to lock
   */
  function mintExchangingPool(uint32 id, uint256 amount) external {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");
    checkParams(amount > 0, ERR_AMOUNT_ZERO, "Distributor/mint amount is zero");

    Pool storage pool = pools[id];
    checkBusiness(pool.state != POOL_STATE_CLOSED, ERR_POOL_IS_CLOSED, "Distributor/pool is closed");

    if (pool.state == POOL_STATE_NOT_START) {
      tryOpenPool(pool);
    }

    uint256 transferedAmount = doTransferIn(pool.tokenAddr, msg.sender, amount);
    uint256 currentPower = accountRecords[id][msg.sender].power;
    updatePower(pool, msg.sender, transferedAmount.add(currentPower));
  }

  /**
   * @notice Claim rewards from pool
   * @param id Id of the pool to claim
   */
  function claim(uint32 id) external {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");

    Pool storage pool = pools[id];
    checkBusiness(pool.state >= POOL_STATE_ACTIVE, ERR_POOL_NOT_STARTED, "Distributor/pool not started");
    claimInternal(pool);
  }

  /**
   * @notice Exit from the exchanging pool
   * @param id Id of the pool to exit
   */
  function exitExchangingPool(uint32 id) external {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");

    Pool storage pool = pools[id];
    checkBusiness(pool.state >= POOL_STATE_ACTIVE, ERR_POOL_NOT_STARTED, "Distributor/pool not started");

    address payable account = msg.sender;
    uint256 amount = accountRecords[id][account].power;
    if (amount == 0) {
      return;
    }
    claimInternal(pool);
    updatePower(pool, account, 0);
    doTransferOut(pool.tokenAddr, account, amount);
    emit MinerExited(account, id, amount);
  }

  /**
   * @notice Close a lending pool
   * @param rToken The lending market address bound with the pool that will be closed
   */
  function closeLendingPool(address rToken) external {
    check(
      orchestrator.getMarketController() == msg.sender,
      ERR_TYPE_AUTH,
      ERR_ONLY_CONTROLLER,
      "Distributor/only market controller is allowed"
    );
    uint32 id = tokenToPoolSeq[rToken] - 1;
    expect(id < pools.length, ERR_UNEXPECTED_POOL_ID, "Distributor/got unexpected pool id for the rToken");
    closePoolInternal(pools[id]);
  }

  //============================================================================
  // Querying methods
  //============================================================================

  /**
   * @notice Query if a pool is in active state
   * @param token The market address of LP token address bound with the pool
   * @return Whether or not the pool active
   */
  function isPoolActive(address token) external view returns (bool) {
    uint32 id = tokenToPoolSeq[token] - 1;
    if (id >= pools.length) return false;
    return pools[id].state == POOL_STATE_ACTIVE;
  }

  /**
   * @notice Query a pool by `id`
   * @param id Id of the pool to query
   * @return The pool object queried
   */
  function getPool(uint32 id) external view returns (Pool memory) {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");
    return pools[id];
  }

  /**
   * @notice Get all pools
   * @return Array of pool objects
   */
  function getAllPools() external view returns (Pool[] memory) {
    return pools;
  }

  /**
   * @notice Get the total number of the pools
   * @return Number of the pools
   */
  function totalPools() external view returns (uint32) {
    return uint32(pools.length);
  }

  /**
   * @notice Get account record of all pools for a user
   * @param account Address of the user
   * @return Array of AccountRecord of the user
   */
  function getAccountRecords(address account) external view returns (AccountRecord[] memory) {
    AccountRecord[] memory records = new AccountRecord[](pools.length);
    for (uint256 i = 0; i < pools.length; i++) {
      records[i] = accountRecords[uint32(i)][account];
    }
    return records;
  }

  /**
   * @notice Get account record of a specific pool for a user
   * @param account Address of the account
   * @param id Id of the pool to query account record
   * @return AccountRecord object of the user in the specific pool
   */
  function getAccountRecord(address account, uint32 id) external view returns (AccountRecord memory) {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");
    return accountRecords[id][account];
  }

  /**
   * @notice Get stats info of the distributor contract
   * @return DistributorStats object
   */
  function getDistributorStats() external view returns (DistributorStats memory) {
    return
      DistributorStats({
        rewardsPerBlock: rewardsPerBlock,
        mineStartBlock: mineStartBlock,
        nextHalvingBlock: nextHalvingBlock,
        activePools: activePools,
        totalPools: uint32(pools.length)
      });
  }

  //============================================================================
  // Governance methods
  //============================================================================

  /**
   * @notice Create a new lending pool for a money market with a specific delay before launching
   * @param rToken Address of the money market bound with the new created pool
   * @param startBlock When will the pool be launched
   */
  function createLendingPool(address rToken, uint256 startBlock) external onlyCouncil {
    checkParams(startBlock > getCurrentBlockNumber(), ERR_START_BLOCK_SMALL, "Distributor/startBlock too small");

    bool isListed = Controller(orchestrator.getMarketController()).isListedMarket(rToken);
    checkBusiness(isListed, ERR_MARKET_NOT_LISTED, "Distributor/market is not listed");
    checkBusiness(
      tokenToPoolSeq[rToken] == 0,
      ERR_POOL_ALREADY_CREATED,
      "Distributor/pool for the market already created"
    );

    uint32 id = uint32(pools.length);
    Pool memory pool = Pool({
      id: id,
      ptype: POOL_TYPE_LENDING,
      tokenAddr: rToken,
      state: POOL_STATE_NOT_START,
      rewardIndex: 0,
      lastBlockNumber: 0,
      accumulatedPower: 0,
      accumulatedTokens: 0,
      totalPower: 0,
      startBlock: startBlock
    });
    pools.push(pool);
    tokenToPoolSeq[rToken] = id + 1;

    emit PoolCreated(pool.id, pool.ptype, startBlock);
  }

  /**
   * @notice Create a new exchanging pool for a LP token with a specific delay before launching
   * @param lpToken Address of the LP token bound with the new created pool
   * @param startBlock When will the pool be launched
   */
  function createExchangingPool(address lpToken, uint256 startBlock) external onlyCouncil {
    checkParams(startBlock > getCurrentBlockNumber(), ERR_START_BLOCK_SMALL, "Distributor/startBlock too small");
    checkBusiness(
      tokenToPoolSeq[lpToken] == 0,
      ERR_POOL_ALREADY_CREATED,
      "Distributor/pool for the exchanger already created"
    );

    uint32 id = uint32(pools.length);
    Pool memory pool = Pool({
      id: id,
      ptype: POOL_TYPE_EXCHANGING,
      tokenAddr: lpToken,
      state: POOL_STATE_NOT_START,
      rewardIndex: 0,
      lastBlockNumber: 0,
      accumulatedPower: 0,
      accumulatedTokens: 0,
      totalPower: 0,
      startBlock: startBlock
    });
    pools.push(pool);
    tokenToPoolSeq[lpToken] = id + 1;

    emit PoolCreated(pool.id, pool.ptype, startBlock);
  }

  /**
   * @notice Close a pool by `id`
   * @param id Id of the pool to close
   */
  function closePool(uint32 id) external onlyCouncil {
    checkParams(id < pools.length, ERR_POOL_ID_OUTOF_RANGE, "Distributor/pool id out of range");
    checkBusiness(
      pools[id].ptype != POOL_TYPE_LENDING,
      ERR_CLOSE_LENDING_POOL_DIRECTLY,
      "Distributor/should not close lending pool directly"
    );
    closePoolInternal(pools[id]);
  }

  //============================================================================
  // Internal methods
  //============================================================================

  function closePoolInternal(Pool storage pool) internal {
    checkBusiness(
      pool.state == POOL_STATE_ACTIVE,
      ERR_POOL_NOT_ACTIVE,
      "Distributor/should not close pool which is not active"
    );
    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i].state == POOL_STATE_ACTIVE) {
        updatePool(pools[i], 0);
      }
    }
    activePools -= 1;
    pool.state = POOL_STATE_CLOSED;
    emit PoolClosed(pool.id);
  }

  function updatePower(
    Pool storage pool,
    address account,
    uint256 newPower
  ) internal {
    AccountRecord storage record = accountRecords[pool.id][account];
    checkParams(newPower <= uint128(-1), ERR_UPDATE_POWER_OVERFLOW, "Distributor/new power overflow");
    int256 addedPower = int256(newPower) - int256(record.power);
    updatePool(pool, addedPower);

    uint256 rewardIndex = pool.rewardIndex;
    if (addedPower < 0) {
      record.settled = rewardIndex.mul(record.power).sub(record.mask).div(MANTISSA).add(record.settled);
      record.mask = rewardIndex.mul(newPower);
    } else if (addedPower > 0) {
      record.mask = record.mask.add(pool.rewardIndex.mul(uint256(addedPower)));
    }
    record.power = newPower;
  }

  function updatePool(Pool storage pool, int256 addedPower) internal {
    uint256 currentBlockNumber = getCurrentBlockNumber();
    if (pool.lastBlockNumber != currentBlockNumber) {
      tryHalving();
      pool.totalPower = safeAddUnsignedSigned(
        pool.totalPower,
        pool.accumulatedPower,
        ERR_TOTAL_POWER_CALC,
        "Distributor/Calculate total power failed"
      );
      uint256 newMinedTokens = tokenMinedWithin(pool.lastBlockNumber, currentBlockNumber);
      if (pool.totalPower != 0) {
        uint256 totalMinedTokens = pool.accumulatedTokens.add(newMinedTokens);
        pool.rewardIndex = pool.rewardIndex.add(totalMinedTokens.mul(MANTISSA).div(pool.totalPower));
        pool.accumulatedTokens = 0;
      } else {
        pool.accumulatedTokens = pool.accumulatedTokens.add(newMinedTokens);
      }
      pool.lastBlockNumber = currentBlockNumber;
      pool.accumulatedPower = 0;
    }
    if (addedPower != 0) {
      pool.accumulatedPower = safeAddSigned(
        pool.accumulatedPower,
        addedPower,
        ERR_ACCUMULATED_POWER_CALC,
        "Distributor/Calculate accmulated power failed"
      );
    }
  }

  function tryOpenPool(Pool storage pool) internal {
    checkBusiness(pool.state == POOL_STATE_NOT_START, ERR_POOL_ALREADY_STARTED, "Distributor/pool already started");

    uint256 currentBlockNumber = getCurrentBlockNumber();
    checkBusiness(currentBlockNumber >= pool.startBlock, ERR_OPEN_TIME_NOT_UP, "Distributor/time not up");
    pool.state = POOL_STATE_ACTIVE;
    pool.lastBlockNumber = currentBlockNumber;
    activePools += 1;
    if (mineStartBlock == 0) {
      uint256 decimals = RDS(orchestrator.getRDS()).decimals();
      rewardsPerBlock = 4 * (10**decimals);
      mineStartBlock = currentBlockNumber;
      nextHalvingBlock = currentBlockNumber.add(BLOCKS_PER_YEAR);
    }
  }

  function claimInternal(Pool storage pool) internal returns (uint256) {
    updatePool(pool, 0);

    AccountRecord storage record = accountRecords[pool.id][msg.sender];
    uint256 rewardIndex = pool.rewardIndex;
    uint256 claimed = rewardIndex.mul(record.power).sub(record.mask).div(MANTISSA).add(record.settled);
    if (claimed > 0) {
      RDS(orchestrator.getRDS()).mint(msg.sender, claimed);
      record.claimed = record.claimed.add(claimed);
      record.settled = 0;
    }
    record.mask = rewardIndex.mul(record.power);
    emit MinerClaimed(msg.sender, pool.id, claimed);
    return claimed;
  }

  function doTransferIn(
    address addr,
    address from,
    uint256 amount
  ) internal returns (uint256) {
    EIP20NonStandardInterface token = EIP20NonStandardInterface(addr);
    uint256 balanceBefore = token.balanceOf(address(this));
    token.transferFrom(from, address(this), amount);

    bool success;
    assembly {
      switch returndatasize()
        case 0 {
          // This is a non-standard ERC-20
          success := not(0) // set success to true
        }
        case 32 {
          // This is a compliant ERC-20
          returndatacopy(0, 0, 32)
          success := mload(0) // Set `success = returndata` of external call
        }
        default {
          // This is an excessively non-compliant ERC-20, revert.
          revert(0, 0)
        }
    }
    expect(success, ERR_TRANSFER_IN_FAILED, "Distributor/transfer in failed");

    // Calculate the amount that was *actually* transferred
    uint256 balanceAfter = token.balanceOf(address(this));
    expect(balanceAfter >= balanceBefore, ERR_TRANSFER_IN_OVERFLOW, "Distributor/transfer in overflow");
    return balanceAfter - balanceBefore;
  }

  function doTransferOut(
    address addr,
    address payable to,
    uint256 amount
  ) internal {
    EIP20NonStandardInterface token = EIP20NonStandardInterface(addr);
    token.transfer(to, amount);

    bool success;
    assembly {
      switch returndatasize()
        case 0 {
          // This is a non-standard ERC-20
          success := not(0) // set success to true
        }
        case 32 {
          // This is a complaint ERC-20
          returndatacopy(0, 0, 32)
          success := mload(0) // Set `success = returndata` of external call
        }
        default {
          // This is an excessively non-compliant ERC-20, revert.
          revert(0, 0)
        }
    }
    expect(success, ERR_TRANSFER_OUT_FAILED, "Distributor/transfer out failed");
  }

  function tryHalving() internal {
    uint256 currentBlockNumber = getCurrentBlockNumber();
    if (currentBlockNumber >= nextHalvingBlock) {
      rewardsPerBlock = rewardsPerBlock.div(2);
      nextHalvingBlock = currentBlockNumber.add(BLOCKS_PER_YEAR);
    }
  }

  function tokenMinedWithin(uint256 startBlock, uint256 endBlock) internal view returns (uint256) {
    return (endBlock - startBlock).mul(rewardsPerBlock).div(activePools);
  }

  function getCurrentBlockNumber() internal view returns (uint256) {
    return block.number;
  }

  function safeAddUnsignedSigned(
    uint256 current,
    int256 addend,
    uint8 errDetail,
    string memory message
  ) internal pure returns (uint256) {
    if (addend >= 0) {
      return current + uint256(addend);
    }
    uint256 result = current - uint256(-addend);
    if (result > current) {
      bytes memory context = abi.encodePacked(
        message,
        ", current: ",
        current.toString(),
        ", addend: ",
        addend.toString()
      );
      checkMath(false, errDetail, string(context));
    }

    return result;
  }

  function safeAddSigned(
    int256 a,
    int256 b,
    uint8 errDetail,
    string memory message
  ) internal pure returns (int256) {
    int256 c = a + b;
    if ((b < 0 && c >= a) || (b > 0 && c <= a)) {
      bytes memory context = abi.encodePacked(message, ", a: ", a.toString(), ", b: ", b.toString());
      checkMath(false, errDetail, string(context));
    }
    return c;
  }

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_DISTRIBUTOR;
  }
}
