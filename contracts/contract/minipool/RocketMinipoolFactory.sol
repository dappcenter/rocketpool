pragma solidity 0.5.8;

// Contracts
import "../../RocketBase.sol";
import "./RocketMinipool.sol";
// Interfaces
import "../../interface/settings/RocketMinipoolSettingsInterface.sol";
// Libraries
import "../../lib/SafeMath.sol";


/***
   * Note: Since this contract handles contract creation by other contracts, it's deployment gas usage will be high depending on the amount of contracts it can create.
***/ 

/// @title Creates minipool contracts for the nodes
/// @author David Rugendyke

contract RocketMinipoolFactory is RocketBase {

    /*** Libs  *****************/

    using SafeMath for uint;


    /*** Contracts *************/

    RocketMinipoolSettingsInterface rocketMinipoolSettings = RocketMinipoolSettingsInterface(0);            // Settings for the minipools 

    
    /*** Events *************/

    event ContractCreated (
        bytes32 name, 
        address contractAddress
    );


    /*** Methods ***************/

    /// @dev RocketFactory constructor
    constructor(address _rocketStorageAddress) RocketBase(_rocketStorageAddress) public {
        // Version
        version = 1;
    }

    /// @dev Create a new RocketMinipool contract, deploy to the etherverse and return the address to the caller
    /// @dev Note that the validation and logic for creation should be done in the calling contract
    /// @param _nodeOwner The node owner of the minipool contract
    /// @param _durationID Staking duration ID
    /// @param _validatorPubkey The validator's pubkey to be submitted to the casper deposit contract for the deposit
    /// @param _validatorSignature The validator's signature to be submitted to the casper deposit contract for the deposit
    /// @param _validatorDepositDataRoot The validator's deposit data SSZ hash tree root to be submitted to the casper deposit contract for the deposit
    /// @param _etherDeposited Ether amount deposited by the node owner
    /// @param _rplDeposited RPL amount deposited by the node owner
    /// @param _trusted Is this node trusted?
    function createRocketMinipool(address _nodeOwner, string memory _durationID, bytes memory _validatorPubkey, bytes memory _validatorSignature, bytes32 _validatorDepositDataRoot, uint256 _etherDeposited, uint256 _rplDeposited, bool _trusted) public onlyLatestContract("rocketPool", msg.sender) returns(address) {
        // Do some initial checks
        rocketMinipoolSettings = RocketMinipoolSettingsInterface(getContractAddress("rocketMinipoolSettings"));
        // Can we create one?
        require(rocketMinipoolSettings.getMinipoolCanBeCreated() == true, "Minipool creation is currently disabled.");
        // Check if node is enabled
        require(rocketStorage.getBool(keccak256(abi.encodePacked("node.active", _nodeOwner))), "Node is inactive and cannot create minipools.");
        // Always requires some ether if not trusted
        if (_trusted) { require(_etherDeposited == 0, "Ether deposit size must be 0 for a trusted node."); }
        else { require(_etherDeposited == rocketMinipoolSettings.getMinipoolLaunchAmount().div(2), "Ether deposit size must be half of the Casper deposit size for an untrusted node."); }
        // Ok create the nodes contract now, this is the address where their ether/rpl deposits will reside 
        address newContractAddress = address(new RocketMinipool(address(rocketStorage), _nodeOwner, _durationID, _validatorPubkey, _validatorSignature, _validatorDepositDataRoot, _etherDeposited, _rplDeposited, _trusted));
        // Emit created event
        emit ContractCreated(keccak256(abi.encodePacked("rocketMinipool")), newContractAddress);
        // Return contract address
        return newContractAddress;
    }

}