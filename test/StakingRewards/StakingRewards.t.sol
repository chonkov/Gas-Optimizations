// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {StakingRewards} from "../../src/StakingRewards/StakingRewards.sol";
import {ERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingRewardsTest is Test {
    IERC20 public rewardsToken;
    IERC20 public stakingToken;

    StakingRewards public stakingRewards;

    function setUp() public {
        rewardsToken = new Token("Reward Token", "RWD");
        stakingToken = new Token("Staking Token", "STK");

        stakingRewards = new StakingRewards(address(this),address(this),address(rewardsToken),address(stakingToken));
    }

    // 1,009,209
    function testDeployment() public {
        new StakingRewards(address(0),address(0),address(0),address(0));
    }

    // 15,807
    function testSetRewardsDuration() public {
        stakingRewards.setRewardsDuration(1 days);
    }

    // 137,372
    function testNotifyRewardAmount() public {
        Token(address(rewardsToken)).mint(address(stakingRewards), 6048000);
        stakingRewards.notifyRewardAmount(6048000);
    }

    // 529,526
    function testRecoverERC20() public {
        Token randomToken = new Token("Random Token", "RND");
        randomToken.mint(address(stakingRewards), 1);

        stakingRewards.recoverERC20(address(randomToken), 1);
    }

    // 7,723
    function testLastTimeRewardApplicable() public {
        uint256 lastUpdate = stakingRewards.lastTimeRewardApplicable();
        assertEq(lastUpdate, 0);
    }

    // 16,062
    function testRewardPerToken() public {
        // @note why is the `_totalSupply` variable at index 12 and not 13
        vm.store(address(stakingRewards), bytes32(uint256(12)), bytes32(uint256(10)));
        assertEq(stakingRewards.totalSupply(), 10);
        stakingRewards.rewardPerToken();
    }

    // 32,229
    function testStakeFail() public {
        vm.expectRevert("Cannot stake 0");
        stakingRewards.stake(0);
    }

    // 29,845
    function testWithdrawFail() public {
        vm.expectRevert("Cannot withdraw 0");
        stakingRewards.withdraw(0);
    }
}
