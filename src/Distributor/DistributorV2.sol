// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {LooksRareToken} from "./LooksRareToken.sol";

/**
 * @title Distributor
 * @notice It handles the distribution of LOOKS token.
 * It auto-adjusts block rewards over a set number of periods.
 */
contract DistributorV2 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for LooksRareToken;

    error DistributorV2_InvalidAmount(uint256);

    struct StakingPeriod {
        uint256 rewardPerBlockForStaking;
        uint256 rewardPerBlockForOthers;
        uint256 periodLengthInBlock;
    }

    struct UserInfo {
        uint256 amount; // Amount of staked tokens provided by user
        uint256 rewardDebt; // Reward debt
    }

    // Precision factor for calculating rewards
    uint256 public constant PRECISION_FACTOR = 10 ** 12;

    LooksRareToken public immutable looksRareToken;

    address public immutable tokenSplitter;

    // Number of reward periods
    uint256 public immutable NUMBER_PERIODS;

    // Block number when rewards start
    uint256 public immutable START_BLOCK;

    // Accumulated tokens per share
    uint256 public accTokenPerShare;

    // Current phase for rewards
    uint256 public currentPhase;

    // Block number when rewards end
    uint256 public endBlock;

    // Block number of the last update
    uint256 public lastRewardBlock;

    // Tokens distributed per block for other purposes (team + treasury + trading rewards)
    uint256 public rewardPerBlockForOthers;

    // Tokens distributed per block for staking
    uint256 public rewardPerBlockForStaking;

    // Total amount staked
    uint256 public totalAmountStaked;

    mapping(uint256 => StakingPeriod) public stakingPeriod;

    mapping(address => UserInfo) public userInfo;

    event Compound(address indexed user, uint256 harvestedAmount);
    event Deposit(address indexed user, uint256 amount, uint256 harvestedAmount);
    event NewRewardsPerBlock(
        uint256 indexed currentPhase,
        uint256 startBlock,
        uint256 rewardPerBlockForStaking,
        uint256 rewardPerBlockForOthers
    );
    event Withdraw(address indexed user, uint256 amount, uint256 harvestedAmount);

    /**
     * @notice Constructor
     * @param _looksRareToken LOOKS token address
     * @param _tokenSplitter token splitter contract address (for team and trading rewards)
     * @param _startBlock start block for reward program
     * @param _rewardsPerBlockForStaking array of rewards per block for staking
     * @param _rewardsPerBlockForOthers array of rewards per block for other purposes (team + treasury + trading rewards)
     * @param _periodLengthesInBlocks array of period lengthes
     * @param _numberPeriods number of periods with different rewards/lengthes (e.g., if 3 changes --> 4 periods)
     */
    constructor(
        address _looksRareToken,
        address _tokenSplitter,
        uint256 _startBlock,
        uint256[] memory _rewardsPerBlockForStaking,
        uint256[] memory _rewardsPerBlockForOthers,
        uint256[] memory _periodLengthesInBlocks,
        uint256 _numberPeriods
    ) {
        // @note Custom error
        // @note In original implementation on line 98 && 99, the same checks are made. One of the checks should be about `_rewardsPerBlockForOthers`
        require(
            (_periodLengthesInBlocks.length == _numberPeriods) && (_rewardsPerBlockForStaking.length == _numberPeriods)
                && (_rewardsPerBlockForOthers.length == _numberPeriods),
            "Distributor: Lengthes must match numberPeriods"
        );

        // 1. Operational checks for supply
        uint256 nonCirculatingSupply =
            LooksRareToken(_looksRareToken).SUPPLY_CAP() - LooksRareToken(_looksRareToken).totalSupply();

        uint256 amountTokensToBeMinted;

        for (uint256 i = 0; i < _numberPeriods; i++) {
            amountTokensToBeMinted += (_rewardsPerBlockForStaking[i] * _periodLengthesInBlocks[i])
                + (_rewardsPerBlockForOthers[i] * _periodLengthesInBlocks[i]);

            stakingPeriod[i] = StakingPeriod({
                rewardPerBlockForStaking: _rewardsPerBlockForStaking[i],
                rewardPerBlockForOthers: _rewardsPerBlockForOthers[i],
                periodLengthInBlock: _periodLengthesInBlocks[i]
            });
        }

        // @note Custom error
        require(amountTokensToBeMinted == nonCirculatingSupply, "Distributor: Wrong reward parameters");

        // 2. Store values
        looksRareToken = LooksRareToken(_looksRareToken);
        tokenSplitter = _tokenSplitter;
        rewardPerBlockForStaking = _rewardsPerBlockForStaking[0];
        rewardPerBlockForOthers = _rewardsPerBlockForOthers[0];

        START_BLOCK = _startBlock;
        endBlock = _startBlock + _periodLengthesInBlocks[0];

        NUMBER_PERIODS = _numberPeriods;

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = _startBlock;
    }

    /**
     * @notice Deposit staked tokens and compounds pending rewards
     * @param amount amount to deposit (in LOOKS)
     */
    function deposit(uint256 amount) external nonReentrant {
        // @note Custom error
        if (amount == 0) revert DistributorV2_InvalidAmount(amount);
        //   require(amount > 0, "Deposit: Amount must be > 0");

        // Update pool information
        _updatePool();

        // Transfer LOOKS tokens to this contract
        looksRareToken.safeTransferFrom(msg.sender, address(this), amount);

        // @note Cache `userInfo[msg.sender].amount` & save two warm sloads on line 167 & 168
        // @note During the initial deposit, only one warm sload will be saved due to line 161
        uint256 currentUserAmount = userInfo[msg.sender].amount;
        uint256 pendingRewards;

        // @note Cache `accTokenPerShare`
        uint256 _accTokenPerShare = accTokenPerShare;

        // If not new deposit, calculate pending rewards (for auto-compounding)
        if (currentUserAmount > 0) {
            pendingRewards =
                ((currentUserAmount * _accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;
        }

        // Adjust user information
        uint256 newUserAmount = currentUserAmount + amount + pendingRewards;
        userInfo[msg.sender].amount = newUserAmount;
        userInfo[msg.sender].rewardDebt = (newUserAmount * _accTokenPerShare) / PRECISION_FACTOR;

        // Increase totalAmountStaked
        totalAmountStaked = totalAmountStaked + (amount + pendingRewards);

        emit Deposit(msg.sender, amount, pendingRewards);
    }

    /**
     * @notice Compound based on pending rewards
     */
    function harvestAndCompound() external nonReentrant {
        // Update pool information
        _updatePool();

        // @note Cache `userInfo[msg.sender].amount`
        uint256 currentUserAmount = userInfo[msg.sender].amount;
        // @note Cache `accTokenPerShare`
        uint256 _accTokenPerShare = accTokenPerShare;

        // Calculate pending rewards
        uint256 pendingRewards =
            ((currentUserAmount * _accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;

        // Return if no pending rewards
        if (pendingRewards == 0) {
            // It doesn't throw revertion (to help with the fee-sharing auto-compounding contract)
            return;
        }

        // Adjust user amount for pending rewards
        uint256 newUserAmount = currentUserAmount + pendingRewards;
        userInfo[msg.sender].amount = newUserAmount;

        // Adjust totalAmountStaked
        totalAmountStaked = totalAmountStaked + pendingRewards;

        // Recalculate reward debt based on new user amount
        userInfo[msg.sender].rewardDebt = (newUserAmount * _accTokenPerShare) / PRECISION_FACTOR;

        emit Compound(msg.sender, pendingRewards);
    }

    /**
     * @notice Update pool rewards
     */
    function updatePool() external nonReentrant {
        _updatePool();
    }

    /**
     * @notice Withdraw staked tokens and compound pending rewards
     * @param amount amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        uint256 currentUserAmount = userInfo[msg.sender].amount;
        // @note Custom error
        if (amount == 0 || currentUserAmount < amount) revert DistributorV2_InvalidAmount(amount);
        //   require(
        //       (userInfo[msg.sender].amount >= amount) && (amount > 0),
        //       "Withdraw: Amount must be > 0 or lower than user balance"
        //   );

        // Update pool
        _updatePool();

        uint256 _accTokenPerShare = accTokenPerShare;

        // Calculate pending rewards
        uint256 pendingRewards =
            ((currentUserAmount * _accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;

        // Adjust user information
        userInfo[msg.sender].amount = currentUserAmount + pendingRewards - amount;
        userInfo[msg.sender].rewardDebt = (currentUserAmount * _accTokenPerShare) / PRECISION_FACTOR;

        // Adjust total amount staked
        totalAmountStaked = totalAmountStaked + pendingRewards - amount;

        // Transfer LOOKS tokens to the sender
        looksRareToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, pendingRewards);
    }

    /**
     * @notice Withdraw all staked tokens and collect tokens
     */
    function withdrawAll() external nonReentrant {
        uint256 currentUserAmount = userInfo[msg.sender].amount;
        // @note Custom error
        if (currentUserAmount == 0) revert DistributorV2_InvalidAmount(currentUserAmount);
        //   require(userInfo[msg.sender].amount > 0, "Withdraw: Amount must be > 0");

        // Update pool
        _updatePool();

        // Calculate pending rewards and amount to transfer (to the sender)
        uint256 pendingRewards =
            ((currentUserAmount * accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;

        uint256 amountToTransfer = currentUserAmount + pendingRewards;

        // Adjust total amount staked
        totalAmountStaked = totalAmountStaked - currentUserAmount;

        // Adjust user information
        userInfo[msg.sender].amount = 0;
        userInfo[msg.sender].rewardDebt = 0;

        // Transfer LOOKS tokens to the sender
        looksRareToken.safeTransfer(msg.sender, amountToTransfer);

        emit Withdraw(msg.sender, amountToTransfer, pendingRewards);
    }

    /**
     * @notice Calculate pending rewards for a user
     * @param user address of the user
     * @return Pending rewards
     */
    function calculatePendingRewards(address user) external view returns (uint256) {
        if ((block.number > lastRewardBlock) && (totalAmountStaked != 0)) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);

            uint256 tokenRewardForStaking = multiplier * rewardPerBlockForStaking;

            uint256 adjustedEndBlock = endBlock;
            uint256 adjustedCurrentPhase = currentPhase;

            // Check whether to adjust multipliers and reward per block
            while ((block.number > adjustedEndBlock) && (adjustedCurrentPhase < (NUMBER_PERIODS - 1))) {
                // Update current phase
                adjustedCurrentPhase++;

                // Update rewards per block
                uint256 adjustedRewardPerBlockForStaking = stakingPeriod[adjustedCurrentPhase].rewardPerBlockForStaking;

                // Calculate adjusted block number
                uint256 previousEndBlock = adjustedEndBlock;

                // Update end block
                adjustedEndBlock = previousEndBlock + stakingPeriod[adjustedCurrentPhase].periodLengthInBlock;

                // Calculate new multiplier
                uint256 newMultiplier = (block.number <= adjustedEndBlock)
                    ? (block.number - previousEndBlock)
                    : stakingPeriod[adjustedCurrentPhase].periodLengthInBlock;

                // Adjust token rewards for staking
                tokenRewardForStaking += (newMultiplier * adjustedRewardPerBlockForStaking);
            }

            uint256 adjustedTokenPerShare =
                accTokenPerShare + (tokenRewardForStaking * PRECISION_FACTOR) / totalAmountStaked;

            return (userInfo[user].amount * adjustedTokenPerShare) / PRECISION_FACTOR - userInfo[user].rewardDebt;
        } else {
            return (userInfo[user].amount * accTokenPerShare) / PRECISION_FACTOR - userInfo[user].rewardDebt;
        }
    }

    /**
     * @notice Update reward variables of the pool
     */
    function _updatePool() internal {
        // @note Cache `lastRewardBlock` to save four sloads
        uint256 _lastRewardBlock = lastRewardBlock;
        if (block.number <= _lastRewardBlock) {
            return;
        }

        // @note Cache `totalAmountStaked` to save one additional sload
        uint256 _totalAmountStaked = totalAmountStaked;

        if (_totalAmountStaked == 0) {
            _lastRewardBlock = block.number;
            return;
        }

        // Calculate multiplier
        uint256 multiplier = _getMultiplier(_lastRewardBlock, block.number);

        uint256 _rewardPerBlockForStaking = rewardPerBlockForStaking;
        uint256 _rewardPerBlockForOthers = rewardPerBlockForOthers;

        // Calculate rewards for staking and others
        uint256 tokenRewardForStaking = multiplier * _rewardPerBlockForStaking;
        uint256 tokenRewardForOthers = multiplier * _rewardPerBlockForOthers;

        // Check whether to adjust multipliers and reward per block
        uint256 _endBlock = endBlock;
        while ((block.number > _endBlock) && (currentPhase < (NUMBER_PERIODS - 1))) {
            // Update rewards per block
            _updateRewardsPerBlock(_endBlock);

            // Adjust the end block
            endBlock = _endBlock + stakingPeriod[currentPhase].periodLengthInBlock;

            // Adjust multiplier to cover the missing periods with other lower inflation schedule
            uint256 newMultiplier = _getMultiplier(_endBlock, block.number);

            // Adjust token rewards
            tokenRewardForStaking += (newMultiplier * _rewardPerBlockForStaking);
            tokenRewardForOthers += (newMultiplier * _rewardPerBlockForOthers);
        }

        // Mint tokens only if token rewards for staking are not null
        if (tokenRewardForStaking > 0) {
            // It allows protection against potential issues to prevent funds from being locked
            bool mintStatus = looksRareToken.mint(address(this), tokenRewardForStaking);
            if (mintStatus) {
                accTokenPerShare = accTokenPerShare + ((tokenRewardForStaking * PRECISION_FACTOR) / _totalAmountStaked);
            }

            looksRareToken.mint(tokenSplitter, tokenRewardForOthers);
        }

        // Update last reward block only if it wasn't updated after or at the end block
        if (_lastRewardBlock <= endBlock) {
            lastRewardBlock = block.number;
        }
    }

    /**
     * @notice Update rewards per block
     * @dev Rewards are halved by 2 (for staking + others)
     */
    function _updateRewardsPerBlock(uint256 _newStartBlock) internal {
        // Update current phase
        unchecked {
            ++currentPhase;
        }

        // Update rewards per block
        rewardPerBlockForStaking = stakingPeriod[currentPhase].rewardPerBlockForStaking;
        rewardPerBlockForOthers = stakingPeriod[currentPhase].rewardPerBlockForOthers;

        emit NewRewardsPerBlock(currentPhase, _newStartBlock, rewardPerBlockForStaking, rewardPerBlockForOthers);
    }

    /**
     * @notice Return reward multiplier over the given "from" to "to" block.
     * @param from block to start calculating reward
     * @param to block to finish calculating reward
     * @return the multiplier for the period
     */
    function _getMultiplier(uint256 from, uint256 to) internal view returns (uint256) {
        if (to <= endBlock) {
            return to - from;
        } else if (from >= endBlock) {
            return 0;
        } else {
            return endBlock - from;
        }
    }
}
