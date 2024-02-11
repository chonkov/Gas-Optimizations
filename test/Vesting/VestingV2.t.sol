// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VestingV2} from "../../src/Vesting/VestingV2.sol";
import {ERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VestingV2Test is Test {
    Token public token;
    VestingV2 public vesting;
    address public user = address(111);

    function setUp() public {
        token = new Token("USD Coin", "USDC");
        vesting = new VestingV2(user,uint(1),uint(1000),uint(4000),true);
    }

    // 731,978 - A little less than 14k gas is saved. 5 `sstore`s are omitted but why only 14k when each sstore costs 22,1k?
    // 662,314
    function testVestingDeployment() public {
        new VestingV2(user,uint(1),uint(1000),uint(4000),false);
    }

    //  64,107 - Saved over 2k gas - 1 cold ssload for `cliff` & 1 warm ssload for `_released[address(token)]`
    function testReleasingFail() public {
        uint256 amount = 4000;
        token.mint(address(vesting), amount);

        vm.warp(1000);
        vm.expectRevert();
        vesting.release(token);
    }

    // 92,060 - Over 8k in savings due to the caching of storage vars and most importantly the immutables
    function testReleasing() public {
        uint256 amount = 4000;
        token.mint(address(vesting), amount);

        vm.warp(4001);
        vesting.release(token);
    }

    //  165,228 - with last `release`
    //  173,798 - without it
    function testRevoking() public {
        uint256 amount = 4000;
        token.mint(address(vesting), amount);

        vm.warp(2001);
        vesting.release(token);

        vm.warp(3001);
        vesting.revoke(token);
        //   vesting.release(token);
    }

    //  55,524
    function testRevokeFail() public {
        vesting.revoke(token);
        vm.expectRevert();
        vesting.revoke(token);
    }

    //  49,711
    function testEmergencyRevokeFail() public {
        vesting.emergencyRevoke(token);
        vm.expectRevert();
        vesting.emergencyRevoke(token);
    }
}
