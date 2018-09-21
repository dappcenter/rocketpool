pragma solidity 0.4.24;

// Interfaces
import "./../../interface/RocketStorageInterface.sol";
import "./../../interface/settings/RocketGroupSettingsInterface.sol";


/// @title The contract for a group that operates in Rocket Pool, holds the entities fees and more
/// @author David Rugendyke

contract RocketGroupContract {

    /**** Properties ***********/

    address public owner;                                                       // The group owner that created the contract
    uint8   public version;                                                     // Version of this contract
    uint256 private feePerc = 0;                                                // The fee this groups charges their users given as a % of 1 Ether (eg 0.02 ether = 2%)
    

    /*** Contracts ***************/

    RocketStorageInterface rocketStorage = RocketStorageInterface(0);           // The main Rocket Pool storage contract where primary persistant storage is maintained
    RocketGroupSettingsInterface rocketGroupSettings = RocketGroupSettingsInterface(0);

    /*** Events ******************/
 
    /*** Modifiers ***************/

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyGroupOwner() {
      require(msg.sender == owner, "Only the group owner account can perform this function.");
      _;
    }

    /**
    * @dev Throws if fee percentage is invalid.
    */
    modifier onlyValidFeePerc(uint256 _stakingFeePerc) {
        // Check its a legit amount
        require(_stakingFeePerc >= 0, "User fee cannot be less than 0.");
        require(_stakingFeePerc <= 1 ether, "User fee cannot be greater than 100%.");
        _;
    }

     
    /*** Constructor *************/

    /// @dev RocketGroupContract constructor
    constructor(address _rocketStorageAddress, address _owner, uint256 _stakingFeePerc) public onlyValidFeePerc(_stakingFeePerc) {
        // Version
        version = 1;
        // Update the storage contract address
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        // Set the group owner
        owner = _owner;
        // Set the staking fee percent
        feePerc = _stakingFeePerc;
    }

    /*** Getters *************/

    /// @dev The fee this groups charges their users given as a % of 1 Ether (eg 0.02 ether = 2%)
    function getFeePerc() public view returns(uint256) { 
        // Get the fee for this groups users
        return feePerc;
    }

    /// @dev Get the fee that Rocket Pool charges for this group given as a % of 1 Ether (eg 0.02 ether = 2%)
    function getFeePercRocketPool() public returns(uint256) { 
        // Get the settings
        rocketGroupSettings = RocketGroupSettingsInterface(rocketStorage.getAddress(keccak256(abi.encodePacked("contract.name", "rocketGroupSettings"))));
        // Get the RP fee
        return rocketGroupSettings.getDefaultFee();
    }


    /*** Setters *************/

    /// @dev Set the fee this group charges their users - Given as a % of 1 Ether (eg 0.02 ether = 2%)
    function setFeePerc(uint256 _stakingFeePerc) public onlyGroupOwner onlyValidFeePerc(_stakingFeePerc) returns(bool) {
        // Ok set it
        feePerc = _stakingFeePerc;
        // Done
        return true;
    }
    
    /*** Methods *************/

    

}