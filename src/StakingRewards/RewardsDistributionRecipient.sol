// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract RewardsDistributionRecipient is Ownable {
    address public rewardsDistribution;

    constructor() Ownable(_msgSender()) {}

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }
}
