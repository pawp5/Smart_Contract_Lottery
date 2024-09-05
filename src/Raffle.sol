// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";


/**
 * @title A sample Raffle contract
 * @author Henschel Ogbonna
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, RaffleState raffleState);

    /* Type Declarations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1

    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_startTimeStamp;
    address private s_winner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event RaffleWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = keyHash;
        i_callbackGasLimit = callbackGasLimit;
        i_subId = subId;

        s_startTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN; // RaffleState(0)
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        // Store the participant address
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev Check if the upkeep is needed.
     * The followoing conditions must be met:
     * 1. The interval has been reached
     * 2. The raffle is open
     * 3. There is a balance in the contract
     * 4. There is at least one participant
     * @param -IGNORED
     * @return upkeepNeeded 
     * @return -IGNORED
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool hasBalance = address(this).balance > 0;
        bool hasPlayer = s_players.length > 0;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool timeHasPassed = ((block.timestamp - s_startTimeStamp) > i_interval);
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayer;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes memory /* performData */) external {
        (bool upkeepNeeded,) = checkUpkeep(""); 
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, s_raffleState);
        }

        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true})) // new parameter
            })
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_winner = winner;

        // Reset the raffle state
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_startTimeStamp = block.timestamp;

        // Pay the winner
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit RaffleWinner(winner);
    }

    /**
     * Getters
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    /**
     * Setters
     */
    function setRaffleState(RaffleState state) external {
        s_raffleState = state;
    }
}
