pragma solidity 0.4.24;


import "../../RocketBase.sol";
import "../../interface/RocketNodeInterface.sol";
import "../../interface/RocketPoolInterface.sol";
import "../../interface/deposit/RocketDepositVaultInterface.sol";
import "../../interface/minipool/RocketMinipoolInterface.sol";
import "../../interface/settings/RocketDepositSettingsInterface.sol";
import "../../interface/utils/lists/AddressSetStorageInterface.sol";
import "../../interface/utils/lists/Bytes32QueueStorageInterface.sol";
import "../../lib/SafeMath.sol";


/// @title RocketDeposit - manages deposits into the Rocket Pool network
/// @author Jake Pospischil

contract RocketDeposit is RocketBase {


    /*** Libs  **************/


    using SafeMath for uint256;


    /*** Contracts **************/


    RocketNodeInterface rocketNode = RocketNodeInterface(0);
    RocketPoolInterface rocketPool = RocketPoolInterface(0);
    RocketDepositVaultInterface rocketDepositVault = RocketDepositVaultInterface(0);
    RocketDepositSettingsInterface rocketDepositSettings = RocketDepositSettingsInterface(0);
    AddressSetStorageInterface addressSetStorage = AddressSetStorageInterface(0);
    Bytes32QueueStorageInterface bytes32QueueStorage = Bytes32QueueStorageInterface(0);


    /*** Modifiers ************/


    // Sender must be a super user or the RocketDeposit API
    modifier onlySuperUserOrDepositAPI() {
        require(
            (roleHas("owner", msg.sender) || roleHas("admin", msg.sender)) ||
            msg.sender == rocketStorage.getAddress(keccak256(abi.encodePacked("contract.name", "rocketDepositAPI"))),
            "User is not a super user or RocketDeposit API"
        );
        _;
    }


    /*** Methods ****************/


    // Constructor
    constructor(address _rocketStorageAddress) RocketBase(_rocketStorageAddress) public {
        version = 1;
    }


    // Default payable function - for deposit vault withdrawals
    function() payable public onlyLatestContract("rocketDepositVault", msg.sender) {}


    // Create a new deposit
    function create(address _userID, address _groupID, string _durationID) payable public onlyLatestContract("rocketDepositAPI", msg.sender) returns (bool) {

        // Check deposit amount
        require(msg.value > 0, "Invalid deposit amount sent");

        // Add deposit
        add(_userID, _groupID, _durationID, msg.value);

        // Update queue balance
        uint256 queueBalance = rocketStorage.getUint(keccak256(abi.encodePacked("deposits.queue.balance", _durationID))).add(msg.value);
        rocketStorage.setUint(keccak256(abi.encodePacked("deposits.queue.balance", _durationID)), queueBalance);

        // Transfer deposit amount to vault
        rocketDepositVault = RocketDepositVaultInterface(getContractAddress("rocketDepositVault"));
        require(rocketDepositVault.depositEther.value(msg.value)(), "Deposit could not be transferred to vault");

        // Assign chunks
        assignChunks(_durationID);

        // Return success flag
        return true;

    }


    // Assign chunks while able
    function assignChunks(string _durationID) public onlySuperUserOrDepositAPI() {

        // Get contracts
        rocketNode = RocketNodeInterface(getContractAddress("rocketNode"));
        rocketDepositSettings = RocketDepositSettingsInterface(getContractAddress("rocketDepositSettings"));

        // Deposit settings
        uint256 chunkSize = rocketDepositSettings.getDepositChunkSize();
        uint256 maxChunkAssignments = rocketDepositSettings.getChunkAssignMax();

        // Assign chunks while able
        uint256 chunkAssignments = 0;
        while (
            rocketStorage.getUint(keccak256(abi.encodePacked("deposits.queue.balance", _durationID))) >= chunkSize && // Duration queue balance high enough to assign chunk
            rocketNode.getAvailableNodeCount(_durationID) > 0 && // Nodes (and minipools) with duration are available for assignment
            chunkAssignments++ < maxChunkAssignments // Only assign up to maximum number of chunks
        ) {
            assignChunk(_durationID);
        }

    }


    // Assign chunk
    function assignChunk(string _durationID) private {

        // Get contracts
        rocketPool = RocketPoolInterface(getContractAddress("rocketPool"));
        rocketDepositVault = RocketDepositVaultInterface(getContractAddress("rocketDepositVault"));
        rocketDepositSettings = RocketDepositSettingsInterface(getContractAddress("rocketDepositSettings"));
        addressSetStorage = AddressSetStorageInterface(getContractAddress("utilAddressSetStorage"));
        bytes32QueueStorage = Bytes32QueueStorageInterface(getContractAddress("utilBytes32QueueStorage"));

        // Get random available minipool to assign chunk to
        address miniPoolAddress = rocketPool.getRandomAvailableMinipool(_durationID, msg.value);
        RocketMinipoolInterface miniPool = RocketMinipoolInterface(miniPoolAddress);

        // Check available minipool address
        require(miniPoolAddress != 0x0, "Invalid available minipool");

        // Remaining ether amount to match
        uint256 chunkSize = rocketDepositSettings.getDepositChunkSize();
        uint256 amountToMatch = chunkSize;

        // Withdraw chunk ether from vault
        require(rocketDepositVault.withdrawEther(address(this), chunkSize), "Deposit could not be transferred from vault");

        // Check queued deposits
        // Max number of iterations is (DepositChunkSize / DepositMin) + 1
        while (bytes32QueueStorage.getQueueLength(keccak256(abi.encodePacked("deposits.queue", _durationID))) > 0) {

            // Get deposit details
            bytes32 depositID = bytes32QueueStorage.getQueueItem(keccak256(abi.encodePacked("deposits.queue", _durationID)), 0);
            uint256 queuedAmount = rocketStorage.getUint(keccak256(abi.encodePacked("deposit.queuedAmount", depositID)));
            uint256 stakingAmount = rocketStorage.getUint(keccak256(abi.encodePacked("deposit.stakingAmount", depositID)));

            // Get queued deposit ether amount to match
            uint256 matchAmount = queuedAmount;
            if (matchAmount > amountToMatch) { matchAmount = amountToMatch; }

            // Update remaining ether amount to match
            amountToMatch = amountToMatch.sub(matchAmount);

            // Update deposit queued / staking ether amounts
            queuedAmount = queuedAmount.sub(matchAmount);
            stakingAmount = stakingAmount.add(matchAmount);
            rocketStorage.setUint(keccak256(abi.encodePacked("deposit.queuedAmount", depositID)), queuedAmount);
            rocketStorage.setUint(keccak256(abi.encodePacked("deposit.stakingAmount", depositID)), stakingAmount);

            // Add deposit staking pool details
            uint256 stakingPoolAmount = rocketStorage.getUint(keccak256(abi.encodePacked("deposit.stakingPoolAmount", depositID, miniPoolAddress)));
            if (stakingPoolAmount == 0) { addressSetStorage.addItem(keccak256(abi.encodePacked("deposit.stakingPools", depositID)), miniPoolAddress); }
            rocketStorage.setUint(keccak256(abi.encodePacked("deposit.stakingPoolAmount", depositID, miniPoolAddress)), stakingPoolAmount.add(matchAmount));

            // Transfer matched amount to minipool contract
            require(miniPool.deposit.value(matchAmount)(
                rocketStorage.getAddress(keccak256(abi.encodePacked("deposit.userID", depositID))),
                rocketStorage.getAddress(keccak256(abi.encodePacked("deposit.groupID", depositID)))
            ), "Deposit could not be transferred to minipool");

            // Remove deposit from queue if queued amount depleted
            if (queuedAmount == 0) { bytes32QueueStorage.dequeueItem(keccak256(abi.encodePacked("deposits.queue", _durationID))); }

            // Stop if required ether amount matched
            if (amountToMatch == 0) { break; }

        }

        // Double-check required ether amount has been matched
        require(amountToMatch == 0, "Required ether amount was not matched");

        // Update queue balance
        uint256 queueBalance = rocketStorage.getUint(keccak256(abi.encodePacked("deposits.queue.balance", _durationID))).sub(chunkSize);
        rocketStorage.setUint(keccak256(abi.encodePacked("deposits.queue.balance", _durationID)), queueBalance);

    }


    // Add a deposit
    // Returns the new deposit ID
    function add(address _userID, address _groupID, string _durationID, uint256 _amount) private returns (bytes32) {

        // Get contracts
        bytes32QueueStorage = Bytes32QueueStorageInterface(getContractAddress("utilBytes32QueueStorage"));

        // Get deposit ID
        uint depositIDNonce = rocketStorage.getUint(keccak256(abi.encodePacked("deposit.user.nonce", _userID, _groupID))).add(1);
        rocketStorage.setUint(keccak256(abi.encodePacked("deposit.user.nonce", _userID, _groupID)), depositIDNonce);
        bytes32 depositID = keccak256(abi.encodePacked("deposit", _userID, _groupID, depositIDNonce));
        require(!rocketStorage.getBool(keccak256(abi.encodePacked("deposit.exists", depositID))), "Deposit ID already in use");

        // Set deposit details
        rocketStorage.setBool(keccak256(abi.encodePacked("deposit.exists", depositID)), true);
        rocketStorage.setAddress(keccak256(abi.encodePacked("deposit.userID", depositID)), _userID);
        rocketStorage.setAddress(keccak256(abi.encodePacked("deposit.groupID", depositID)), _groupID);
        rocketStorage.setString(keccak256(abi.encodePacked("deposit.stakingDurationID", depositID)), _durationID);
        rocketStorage.setUint(keccak256(abi.encodePacked("deposit.totalAmount", depositID)), _amount);
        rocketStorage.setUint(keccak256(abi.encodePacked("deposit.queuedAmount", depositID)), _amount);
        // + stakingAmount
        // + stakingPools
        // + stakingPoolAmount

        // Update deposit indexes
        bytes32QueueStorage.enqueueItem(keccak256(abi.encodePacked("deposits.queue", _durationID)), depositID);

        // Return ID
        return depositID;

    }


}

