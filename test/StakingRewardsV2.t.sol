// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {StakingRewardsV2} from "../src/StakingRewards/StakingRewardsV2.sol";
import {ERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingRewardsV2Test is Test {
    IERC20 public rewardsToken;
    IERC20 public stakingToken;

    StakingRewardsV2 public stakingRewards;

    function setUp() public {
        rewardsToken = new Token("Reward Token", "RWD");
        stakingToken = new Token("Staking Token", "STK");

        stakingRewards = new StakingRewardsV2(address(this),address(this),address(rewardsToken),address(stakingToken));
    }

    // 1,042,558
    // 1,062,234 - gas cost of deployment increased after packing storage variables
    function testDeployment() public {
        // Deployment is more expensive when storage variable are made immutable?
        new StakingRewardsV2(address(0),address(0),address(0),address(0));
    }

    // 13,878
    function testSetRewardsDuration() public {
        // Same gas cost even when an entire sload() is saved?
        stakingRewards.setRewardsDuration(1 days);
    }

    // 134,996
    // 94,412 - Significant reduction of gas consumption - more than 40k is saved due to packing variables in a single storage slot
    function testNotifyRewardAmount() public {
        // Around 3,4k gas is saved when storage variables are cached
        Token(address(rewardsToken)).mint(address(stakingRewards), 6048000);
        stakingRewards.notifyRewardAmount(6048000);
    }

    // 527,432
    // 527,410
    function testRecoverERC20() public {
        // A little less than 2,1k gas is saved(cold sload costs 2100 gas)
        Token randomToken = new Token("Random Token", "RND");
        randomToken.mint(address(stakingRewards), 1);

        stakingRewards.recoverERC20(address(randomToken), 1);
    }

    // 7,646
    function testLastTimeRewardApplicable() public {
        // A little less than 100 gas is saved(warm sload costs 100 gas)
        uint256 lastUpdate = stakingRewards.lastTimeRewardApplicable();
        assertEq(lastUpdate, 0);
    }

    // 15,893
    // 14,041 - Over 1,8k gas is saved again only due to packing variables in a single storage
    function testRewardPerToken() public {
        // A little less than 200 gas is saved(warm sload costs 100 gas)
        // `rewardPerToken` also calls `lastTimeRewardApplicable`, which additionally saves almost another 100 gas

        // @note `_totalSupply` variable is at index 11 (correct one)
        vm.store(address(stakingRewards), bytes32(uint256(9)), bytes32(uint256(10)));
        assertEq(stakingRewards.totalSupply(), 10);
        stakingRewards.rewardPerToken();
    }

    // 32,060
    // 30,170
    function testStakeFail() public {
        vm.expectRevert(StakingRewardsV2.InvalidAmount.selector);
        stakingRewards.stake(0);
    }

    // 30,003
    // 27,955
    function testWithdrawFail() public {
        vm.expectRevert(StakingRewardsV2.InvalidAmount.selector);
        stakingRewards.withdraw(0);
    }
}
