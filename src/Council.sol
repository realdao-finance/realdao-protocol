pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./libraries/SafeMath.sol";
import "./AuthBase.sol";

/**
 * @title Council governance contract
 */
contract Council is AuthBase {
  using SafeMath for uint256;

  enum ProposalState { None, Pending, Rejected, Expired, Queued, Canceled, Executed }
  struct Proposal {
    uint256 id;
    address proposer;
    address target;
    uint256 value;
    string signature;
    bytes params;
    uint256 endBlock;
    uint256 startBlock;
    uint256 eta;
    uint256 ayes;
    ProposalState state;
  }

  mapping(uint256 => Proposal) proposals;
  address[] public members;
  uint256 public proposalCount;

  uint256 public maxMembers = 11;
  uint256 public executionDelay = 11520; // 2 days

  uint256 public constant MIN_MEMBERS = 3;
  uint256 public constant MAX_VOTING_PERIOD = 172800; // 30 days
  uint256 public constant MIN_VOTING_PERIOD = 40320; // 7 days
  uint256 public constant MAX_VOTING_DELAY = 57600; // 10 days
  uint256 public constant GRACE_PERIOD = 57600; // 10 days
  uint256 public constant MAX_EXECUTION_DELAY = 172800; // 30 days

  mapping(address => bool) memberMap;
  mapping(uint256 => mapping(address => bool)) proposalVoters;

  uint8 constant ERR_ONLY_COUNCIL_MEMBER = 1;
  uint8 constant ERR_INVALID_VOTING_DELAY = 2;
  uint8 constant ERR_INVALID_VOTING_PERIOD = 3;
  uint8 constant ERR_PROPOSAL_NOT_EXIST = 4;
  uint8 constant ERR_VOTING_TIME_NOT_UP = 5;
  uint8 constant ERR_ALREADY_VOTED = 6;
  uint8 constant ERR_INVALID_MEMBER_COUNT = 7;
  uint8 constant ERR_TRANSACTION_EXECUTION = 8;
  uint8 constant ERR_NOT_QUEUED = 9;
  uint8 constant ERR_EXECUTION_TIME_LOCK = 10;
  uint8 constant ERR_PROPOSAL_STALE = 11;
  uint8 constant ERR_INVALID_MAX_MEMBER = 12;
  uint8 constant ERR_INVALID_EXECUTION_DELAY = 13;
  uint8 constant ERR_NOT_VOTING_STATE = 14;

  event ProposalCreated(
    uint256 id,
    address proposer,
    address target,
    uint256 value,
    string signature,
    bytes params,
    uint256 startBlock,
    uint256 endBlock,
    string desc
  );
  event ProposalVoted(uint256 id, address voter);
  event ProposalExpired(uint256 id);
  event ProposalQueued(uint256 id, uint256 eta);
  event ProposalExecuted(uint256 id);
  event ProposalCanceled(uint256 id, bool success);
  event NewTermStarted(address[] members);
  event NewMaxMembers(uint256 oldVal, uint256 newVal);
  event NewExecutionDelay(uint256 oldVal, uint256 newVal);

  modifier onlyCouncilMember {
    check(
      memberMap[msg.sender],
      ERR_DOMAIN_COUNCIL,
      ERR_TYPE_AUTH,
      ERR_ONLY_COUNCIL_MEMBER,
      "Council/permission only for council member"
    );
    _;
  }

  /**
   * @notice Initialize the council
   * @param _orchestrator The address of the orchestrator contract
   */
  function initialize(address _orchestrator) public override {
    super.initialize(_orchestrator);

    // set members for the first term
    members.push(0x6298194AFa16862870521908caa7e9D138360858);
    members.push(0x5661cdBc2Ff8ffC5eC8f0fb1F551443CE3068ed4);
    members.push(0x2CBD3f5419e25EC484630282AeF645c365dA006A);
    for (uint256 i = 0; i < members.length; i++) {
      memberMap[members[i]] = true;
    }
  }

  /* solium-disable-next-line */
  receive() external payable {}

  /**
   * @notice Lanuch a proposal
   * @param target The target contract address of the proposal
   * @param value Ethers that the proposal will transfer
   * @param signature The signature of the method that is to be called in the proposal
   * @param params The params of the transaction
   * @param delay Delay of the voting time
   * @param votingPeriod Duration of the voting stage
   * @param desc The description of the proposal
   */
  function propose(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata params,
    uint256 delay,
    uint256 votingPeriod,
    string calldata desc
  ) external onlyCouncilMember {
    checkParams(delay > 0 && delay <= MAX_VOTING_DELAY, ERR_INVALID_VOTING_DELAY, "Council/invalid voting delay");
    checkParams(
      votingPeriod <= MAX_VOTING_PERIOD && votingPeriod >= MIN_VOTING_PERIOD,
      ERR_INVALID_VOTING_PERIOD,
      "Council/invalid voting period"
    );
    uint256 startBlock = block.number.add(delay);
    uint256 endBlock = startBlock.add(votingPeriod);

    proposalCount++;
    Proposal memory newProposal = Proposal({
      id: proposalCount,
      proposer: msg.sender,
      target: target,
      value: value,
      signature: signature,
      params: params,
      startBlock: startBlock,
      endBlock: endBlock,
      eta: 0,
      ayes: 1,
      state: ProposalState.Pending
    });
    proposals[newProposal.id] = newProposal;
    proposalVoters[newProposal.id][newProposal.proposer] = true;

    emit ProposalCreated(newProposal.id, msg.sender, target, value, signature, params, startBlock, endBlock, desc);
  }

  /**
   * @notice Vote a proposal
   * @param id Id of the proposal to vote
   */
  function vote(uint256 id) external onlyCouncilMember {
    Proposal storage proposal = proposals[id];
    checkBusiness(id > 0 && proposal.id == id, ERR_PROPOSAL_NOT_EXIST, "Council/proposal not exist");
    checkBusiness(block.number >= proposal.startBlock, ERR_VOTING_TIME_NOT_UP, "Council/voting time not up");
    checkBusiness(!proposalVoters[id][msg.sender], ERR_ALREADY_VOTED, "Council/already voted");
    checkBusiness(proposal.state == ProposalState.Pending, ERR_NOT_VOTING_STATE, "Council/not voting state");

    if (block.number > proposal.endBlock) {
      proposal.state = ProposalState.Expired;
      emit ProposalExpired(id);
      return;
    }

    proposal.ayes++;
    proposalVoters[id][msg.sender] = true;
    emit ProposalVoted(id, proposal.proposer);

    if (proposal.ayes > members.length / 2) {
      // execute(proposal.target, proposal.value, proposal.signature, proposal.params);
      proposal.state = ProposalState.Queued;
      proposal.eta = block.number + executionDelay;
      emit ProposalQueued(id, proposal.eta);
    }
  }

  /**
   * @notice Execute a proposal
   * @param id Id of the proposal to execute
   */
  function execute(uint256 id) external {
    Proposal storage p = proposals[id];
    checkBusiness(id > 0 && p.id == id, ERR_PROPOSAL_NOT_EXIST, "Council/proposal not exist");
    checkBusiness(p.state == ProposalState.Queued, ERR_NOT_QUEUED, "Council/executing proposal is not queued");
    checkBusiness(block.number >= p.eta, ERR_EXECUTION_TIME_LOCK, "Council/proposal hasn't surpassed time lock");
    checkBusiness(block.number <= p.eta.add(GRACE_PERIOD), ERR_PROPOSAL_STALE, "Council/proposal is stale");

    bytes memory callData;
    if (bytes(p.signature).length == 0) {
      callData = p.params;
    } else {
      callData = abi.encodePacked(bytes4(keccak256(bytes(p.signature))), p.params);
    }
    // solium-disable-next-line security/no-call-value
    (bool success, bytes memory data) = p.target.call.value(p.value)(callData);
    bytes memory message = abi.encodePacked("Council/transaction execution failed: ", data);
    checkBusiness(success, ERR_TRANSACTION_EXECUTION, string(message));

    p.state = ProposalState.Executed;
    emit ProposalExecuted(id);
  }

  /**
   * @notice Get council members
   * @return Array of address of council members
   */
  function getMembers() external view returns (address[] memory) {
    return members;
  }

  /**
   * @notice Query a proposal by `id`
   * @param id The id of the proposal to query
   * @return The queried proposal object
   */
  function getProposal(uint256 id) external view returns (Proposal memory) {
    return proposals[id];
  }

  //============================================================================
  // Governance methods
  //============================================================================

  /**
   * @notice Cancel a proposal by `id`
   * @param id Id of the proposal to cancel
   */
  function cancel(uint256 id) external onlyDemocracy {
    Proposal storage p = proposals[id];
    checkBusiness(id > 0 && p.id == id, ERR_PROPOSAL_NOT_EXIST, "Council/proposal not exist");

    bool success = false;
    if (p.state == ProposalState.Queued || p.state == ProposalState.Pending) {
      p.state = ProposalState.Canceled;
      success = true;
    }
    emit ProposalCanceled(id, success);
  }

  /**
   * @notice Start a new term for the council
   * @param newMembers Array of address of the new members
   */
  function startNewTerm(address[] calldata newMembers) external onlyDemocracy {
    uint256 len = newMembers.length;
    checkParams(len >= MIN_MEMBERS && len <= maxMembers, ERR_INVALID_MEMBER_COUNT, "Council/invalid member count");

    for (uint256 i = 0; i < members.length; i++) {
      delete memberMap[members[i]];
    }
    delete members;

    for (uint256 i = 0; i < newMembers.length; i++) {
      memberMap[newMembers[i]] = true;
      members.push(newMembers[i]);
    }
    emit NewTermStarted(newMembers);
  }

  /**
   * @notice Set maxMembers
   * @param val The new value of the maxMember
   */
  function setMaxMembers(uint256 val) external onlyDemocracy {
    checkParams(val > MIN_MEMBERS, ERR_INVALID_MAX_MEMBER, "Council/invalid max member set");
    emit NewMaxMembers(maxMembers, val);
    maxMembers = val;
  }

  /**
   * @notice Set executionDelay
   * @param val The new value of the executionDelay
   */
  function setExecutionDelay(uint256 val) external onlyDemocracy {
    checkParams(
      val > 0 && val <= MAX_EXECUTION_DELAY,
      ERR_INVALID_EXECUTION_DELAY,
      "Council/invalid execution delay set"
    );
    emit NewExecutionDelay(executionDelay, val);
    executionDelay = val;
  }

  //============================================================================
  // Internal methods
  //============================================================================

  function errorDomain() internal override pure returns (uint8) {
    return ERR_DOMAIN_COUNCIL;
  }
}
