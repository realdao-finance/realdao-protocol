pragma solidity ^0.6.0;

/**
 * @title Democracy governance contract
 * @notice WIP
 */
contract Democracy {
  struct Proposal {
    uint256 id;
    address proposer;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] paramsList;
    uint256 startBlock;
    uint256 endBlock;
    uint256[] ayes;
  }

  uint256 public proposalCount;

  mapping(uint256 => Proposal) propoals;

  event ProposalCreated(address sender);

  modifier onlySelf {
    require(msg.sender == address(this), "Democracy/permission denied");
    _;
  }

  /* solium-disable-next-line */
  receive() external payable {}

  function propose() external {}

  function vote() external {}

  function execute(
    address target,
    string calldata signature,
    bytes calldata params
  ) external {
    bytes memory callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), params);
    // solium-disable-next-line security/no-call-value
    (bool success, ) = target.call.value(0)(callData);
    require(success, "Democracy/transaction execution reverted");
  }
}
