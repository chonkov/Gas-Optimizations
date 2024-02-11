// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract VestingV2 is Ownable {
    using SafeERC20 for IERC20;

    event TokensReleased(address token, uint256 amount);
    event TokenVestingRevoked(address token);
    event Log(uint256);

    // @note Make state variables immutable since they never change
    address public immutable beneficiary;
    uint256 public immutable cliff;
    uint256 public immutable start;
    uint256 public immutable duration;
    bool public immutable revocable;

    mapping(address => uint256) private _released;
    mapping(address => bool) private _revoked;

    constructor(address beneficiary_, uint256 start_, uint256 cliffDuration_, uint256 duration_, bool revocable_)
        Ownable(_msgSender())
    {
        // @note Custom errors
        if (beneficiary_ == address(0)) revert();
        if (cliffDuration_ > duration_) revert();
        if (duration_ == 0) revert();
        if (start_ + duration_ <= block.timestamp) revert();
        // require(beneficiary_ != address(0), "TokenVesting: beneficiary is the zero address");
        // // solhint-disable-next-line max-line-length
        // require(cliffDuration_ <= duration_, "TokenVesting: cliff is longer than duration");
        // require(duration_ > 0, "TokenVesting: duration is 0");
        // // solhint-disable-next-line max-line-length
        // require(start_ + duration_ > block.timestamp, "TokenVesting: final time is before current time");

        beneficiary = beneficiary_;
        revocable = revocable_;
        duration = duration_;
        cliff = start_ + cliffDuration_;
        start = start_;
    }

    /**
     * @return the amount of the token released.
     */
    function released(address token) public view returns (uint256) {
        return _released[token];
    }

    /**
     * @return true if the token is revoked.
     */
    function revoked(address token) public view returns (bool) {
        return _revoked[token];
    }

    /**
     * @notice Transfers vested tokens to beneficiary.
     * @param token ERC20 token which is being vested
     */
    function release(IERC20 token) public {
        uint256 released_ = _released[address(token)]; // so far released tokens

        uint256 unreleased = _releasableAmount(token, released_);

        // @note Custom errors
        if (unreleased == 0) revert();
        // require(unreleased > 0, "TokenVesting: no tokens are due");

        _released[address(token)] = released_ + unreleased;

        token.safeTransfer(beneficiary, unreleased);

        emit TokensReleased(address(token), unreleased);
    }

    /**
     * @notice Allows the owner to revoke the vesting. Tokens already vested
     * remain in the contract, the rest are returned to the owner.
     * @param token ERC20 token which is being vested
     */
    function revoke(IERC20 token) public onlyOwner {
        // @note Custom errors
        if (!revocable) revert();
        if (_revoked[address(token)]) revert();
        // require(revocable, "TokenVesting: cannot revoke");
        // require(!_revoked[address(token)], "TokenVesting: token already revoked");

        uint256 balance = token.balanceOf(address(this));
        uint256 released_ = _released[address(token)];

        uint256 unreleased = _releasableAmount(token, released_);
        uint256 refund = balance - unreleased;

        _revoked[address(token)] = true;

        token.safeTransfer(owner(), refund);

        emit TokenVestingRevoked(address(token));
    }

    /**
     * @notice Allows owner to emergency revoke and refund entire balance,
     * including the vested amount. To be used when beneficiary cannot claim
     * anymore, e.g. when he/she has lots its private key.
     * @param token ERC20 which is being vested
     */
    function emergencyRevoke(IERC20 token) public onlyOwner {
        // @note Custom errors
        if (!revocable) revert();
        if (_revoked[address(token)]) revert();
        // require(revocable, "TokenVesting: cannot revoke");
        // require(!_revoked[address(token)], "TokenVesting: token already revoked");

        uint256 balance = token.balanceOf(address(this));

        _revoked[address(token)] = true;

        token.safeTransfer(owner(), balance);

        emit TokenVestingRevoked(address(token));
    }

    /**
     * @dev Calculates the amount that has already vested but hasn't been released yet.
     * @param token ERC20 token which is being vested
     */
    function _releasableAmount(IERC20 token, uint256 released_) private returns (uint256) {
        return _vestedAmount(token, released_);
    }

    /**
     * @dev Calculates the amount that has already vested.
     * @param token ERC20 token which is being vested
     */
    function _vestedAmount(IERC20 token, uint256 released_) private returns (uint256) {
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 totalBalance = currentBalance + released_;

        emit Log(totalBalance);
        emit Log(totalBalance * (block.timestamp - start) / duration - released_);

        if (block.timestamp < cliff) {
            return 0;
        } else if (block.timestamp >= start + duration || _revoked[address(token)]) {
            return totalBalance - released_;
        } else {
            return (totalBalance * (block.timestamp - start)) / duration - released_;
        }
    }
}
