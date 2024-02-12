// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Distributor, LooksRareToken} from "../../src/Distributor/Distributor.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DistributorTest is Test {
    Distributor public distributor;
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
        new Distributor(address(token), address(999), startBlock, rewardsPerBlockForStaking, rewardsPerBlockForOthers, periodLengthesInBlocks, numberPeriods);
        token.transferOwnership(address(distributor));
    }

    // 104,560
    function testSingleDeposit() public {
        uint256 startBlock = 7;
        uint256 amount = 100e18;

        vm.roll(startBlock);

        vm.startPrank(alice);
        token.approve(address(distributor), amount);
        distributor.deposit(amount);
        vm.stopPrank();
    }

    // 214,847
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
}
