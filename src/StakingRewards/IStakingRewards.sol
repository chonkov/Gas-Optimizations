// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IStakingRewards {
    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    // function rewardsDistribution() external view returns (address);

    function rewardsToken() external view returns (IERC20);

    function totalSupply() external view returns (uint256);

    function exit() external;

    function getReward() external;

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;
}
