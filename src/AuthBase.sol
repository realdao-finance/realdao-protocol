pragma solidity ^0.6.0;

import "./interfaces/OrchestratorInterface.sol";
import "./ErrorBase.sol";

abstract contract AuthBase is ErrorBase {
  OrchestratorInterface public orchestrator;

  uint8 constant ERR_NOT_INITIALIZED = 1;
  uint8 constant ERR_ALREADY_INITIALIZED = 2;
  uint8 constant ERR_ONLY_COUNCIL = 3;
  uint8 constant ERR_ONLY_DEMOCRACY = 4;

  modifier onlyCouncil {
    address superior = address(orchestrator);
    check(superior != address(0), ERR_TYPE_AUTH, ERR_NOT_INITIALIZED, "AuthBase/not initialized");

    address sender = msg.sender;
    address guardian = orchestrator.guardian();
    address council = orchestrator.getCouncil();
    address democracy = orchestrator.getDemocracy();
    check(
      sender == council || sender == democracy || sender == guardian || sender == superior,
      ERR_TYPE_AUTH,
      ERR_ONLY_COUNCIL,
      "AuthBase/only permission above council is allowed"
    );
    _;
  }

  modifier onlyDemocracy {
    expect(address(orchestrator) != address(0), ERR_NOT_INITIALIZED, "AuthBase/not initialized");

    address guardian = orchestrator.guardian();
    address democracy = orchestrator.getDemocracy();
    check(
      msg.sender != democracy || msg.sender != guardian,
      ERR_TYPE_AUTH,
      ERR_ONLY_DEMOCRACY,
      "AuthBase/only democracy is allowed"
    );
    _;
  }

  function initialize(address _orchestrator) public virtual {
    expect(address(orchestrator) == address(0), ERR_ALREADY_INITIALIZED, "AuthBase/already initialized");
    orchestrator = OrchestratorInterface(_orchestrator);
  }
}
