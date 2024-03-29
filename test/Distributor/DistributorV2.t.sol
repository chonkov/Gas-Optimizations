// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DistributorV2, LooksRareToken} from "../../src/Distributor/DistributorV2.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DistributorV2Test is Test {
    DistributorV2 public distributor;
    LooksRareToken public token;
    address public alice = address(111);
    address public bob = address(222);

    function setUp() public {
        uint256 startBlock = 7;

        uint256[] memory rewardsPerBlockForStaking = new uint[](1);
        uint256[] memory rewardsPerBlockForOthers = new uint[](1);
        uint256[] memory periodLengthesInBlocks = new uint[](1);

        rewardsPerBlockForStaking[0] = 1e18;
        rewardsPerBlockForOthers[0] = 0;
        periodLengthesInBlocks[0] = 11;

        uint256 numberPeriods = 1;
        uint256 cap = 211e18;

        token = new LooksRareToken(address(this), cap);
        token.mint(alice, 100e18);
        token.mint(bob, 100e18);

        assertEq(token.SUPPLY_CAP() - token.totalSupply(), 11e18);
        assertEq(rewardsPerBlockForStaking[0] * periodLengthesInBlocks[0], 11e18);

        distributor =
        new DistributorV2(address(token), address(999), startBlock, rewardsPerBlockForStaking, rewardsPerBlockForOthers, periodLengthesInBlocks, numberPeriods);
        token.transferOwnership(address(distributor));
    }

    // 104,202 - Over 300 gas saved. First deposit in optimized contract saves 2 sloads
    function testSingleDeposit() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();
    }

    // 213,991 - Over 800 gas saved. Second deposit in optimized contract saves 7 sloads
    function testMultipleDeposit() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();

        vm.roll(startBlock + 2);

        vm.startPrank(bob);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();
    }

    //  16,295
    function testDepositFail() public {
        uint256 startBlock = 7;
        vm.roll(startBlock);

        vm.prank(alice);
        vm.expectRevert();
        distributor.deposit(0);
    }

    //  248,970 - Almost 2k gas saved
    function testHarvestAndCompound() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();

        vm.roll(startBlock + 2);

        vm.startPrank(bob);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();

        vm.roll(startBlock + 3);
        vm.prank(alice);
        distributor.harvestAndCompound();
    }

    //  18,117
    function testWithdrawDistributorFail() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.withdraw(0);
    }

    //  183,199 - A little less than 1k gas saved
    function testWithdrawDistributor() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);

        vm.roll(startBlock + 2);

        distributor.withdraw(amount);

        vm.stopPrank();
    }

    //  18,064
    function testWithdrawAllDistributorFail() public {
        vm.prank(alice);
        vm.expectRevert();
        distributor.withdrawAll();
    }

    //  148,753
    function testWithdrawAllDistributor() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);

        vm.roll(startBlock + 2);

        distributor.withdrawAll();

        vm.stopPrank();
    }

    //  113,824
    function testPendingRewards() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();

        vm.roll(startBlock + 2);

        uint256 rewards = distributor.calculatePendingRewards(alice);
        assertEq(rewards, 2e18);
    }
}
