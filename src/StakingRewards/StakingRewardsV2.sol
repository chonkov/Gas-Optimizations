// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

import {IStakingRewards} from "./IStakingRewards.sol";
import {RewardsDistributionRecipient} from "./RewardsDistributionRecipient.sol";

contract StakingRewardsV2 is IStakingRewards, RewardsDistributionRecipient, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    uint256 public rewardRate = 0;
    uint80 public periodFinish = 0;
    uint80 public rewardsDuration = 7 days;
    uint80 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(address, address _rewardsDistribution, address _rewardsToken, address _stakingToken) {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        uint256 _periodFinish = periodFinish; // @note caching periodFinish to save one additional storage read
        return block.timestamp < _periodFinish ? block.timestamp : _periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        uint256 totalSupply_ = _totalSupply; // @note caching _totalSupply to save one additional storage read
        if (totalSupply_ == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalSupply_);
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (amount == 0) revert InvalidAmount();
        // @note custom error
        // require(amount > 0, "Cannot stake 0");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert InvalidAmount();
        // @note custom error
        // require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;
        emit Withdrawn(msg.sender, amount);
        stakingToken.safeTransfer(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            emit RewardPaid(msg.sender, reward);
            rewardsToken.safeTransfer(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        uint256 _periodFinish = periodFinish; // @note caching for saving one additional storage read
        uint256 _rewardsDuration = rewardsDuration; // @note caching for saving three additional storage reads

        if (block.timestamp >= _periodFinish) {
            rewardRate = reward / _rewardsDuration;
        } else {
            uint256 remaining = _periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / _rewardsDuration;
        }

        uint256 balance = rewardsToken.balanceOf(address(this));
        if (rewardRate > balance / _rewardsDuration) revert InvalidAmount();
        // @note custom error
        // require(rewardRate <= balance / _rewardsDuration, "Provided reward too high");

        lastUpdateTime = uint80(block.timestamp);
        periodFinish = uint80(block.timestamp + _rewardsDuration);
        emit RewardAdded(reward);
    }

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(stakingToken)) revert InvalidAddress();
        // @note custom error
        // require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
        emit Recovered(tokenAddress, tokenAmount);
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        if (block.timestamp <= periodFinish) revert InvalidTimestamp();
        // @note custom error
        // require(
        //     block.timestamp > periodFinish,
        //     "Previous rewards period must be complete before changing the duration for the new period"
        // );
        rewardsDuration = uint80(_rewardsDuration);
        // @note replace `rewardsDuration` with `_rewardsDuration`
        emit RewardsDurationUpdated(_rewardsDuration);
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = uint80(lastTimeRewardApplicable());
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);

    /* ========== ERRORS ========== */

    error InvalidAmount();
    error InvalidAddress();
    error InvalidTimestamp();
}
