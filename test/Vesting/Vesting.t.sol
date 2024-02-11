// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vesting} from "../../src/Vesting/Vesting.sol";
import {ERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VestingTest is Test {
    Token public token;
    Vesting public vesting;
    address public user = address(111);

    function setUp() public {
        token = new Token("USD Coin", "USDC");
        vesting = new Vesting(user,uint(1),uint(1000),uint(4000),true);
    }

    // 745,634
    // 747,783
    function testVestingDeployment() public {
        new Vesting(user,uint(1),uint(1000),uint(4000),false);
    }

    // 66,536
    function testReleasingFail() public {
        uint256 amount = 4000;
        token.mint(address(vesting), amount);

        vm.warp(1000);
        vm.expectRevert();
        vesting.release(token);
    }

    //  100,835
    function testReleasing() public {
        uint256 amount = 4000;
        token.mint(address(vesting), amount);

        vm.warp(4001);
        vesting.release(token);
    }

    // 170,569 - with last `release`
    // 180,761 - without it
    function testRevoking() public {
        uint256 amount = 4000;
        token.mint(address(vesting), amount);

        vm.warp(2001);
        vesting.release(token);

        vm.warp(3001);
        vesting.revoke(token);
        //   vesting.release(token);
    }

    // 57,838
    function testRevokeFail() public {
        vesting.revoke(token);
        vm.expectRevert();
        vesting.revoke(token);
    }

    //  52,123
    function testEmergencyRevokeFail() public {
        vesting.emergencyRevoke(token);
        vm.expectRevert();
        vesting.emergencyRevoke(token);
    }
}
