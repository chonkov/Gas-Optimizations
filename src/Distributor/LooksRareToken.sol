// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract LooksRareToken is ERC20, Ownable {
    uint256 private immutable _SUPPLY_CAP;

    /**
     * @notice Constructor
     * @param _cap supply cap (to prevent abusive mint)
     */
    constructor(address _owner, uint256 _cap) ERC20("LooksRare Token", "LOOKS") Ownable(_owner) {
        _SUPPLY_CAP = _cap;
    }

    /**
     * @notice Mint LOOKS tokens
     * @param account address to receive tokens
     * @param amount amount to mint
     * @return status true if mint is successful, false if not
     */
    function mint(address account, uint256 amount) external onlyOwner returns (bool status) {
        if (totalSupply() + amount <= _SUPPLY_CAP) {
            _mint(account, amount);
            return true;
        }
        return false;
    }

    /**
     * @notice View supply cap
     */
    function SUPPLY_CAP() external view returns (uint256) {
        return _SUPPLY_CAP;
    }
}
