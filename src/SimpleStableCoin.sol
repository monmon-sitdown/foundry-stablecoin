// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleStableCoin
 * @author monmon
 * @dev A simple stablecoin contract with minting and burning capabilities, owned by a single address.
 *
 * This is the contract meant to be governed by CollateralManager.sol.
 * This contract is just the ERC20 implementation of our stablecoin system.
 */
contract SimpleStableCoin is ERC20Burnable, Ownable {
    error SSC_MustBeMoreThanZero();
    error SSC_BurnAmountExceedsBalance();
    error SSC_NotZeroAddress();

    /**
     * @dev Sets the name and symbol for the stablecoin.
     * The contract deployer is set as the initial owner.
     */
    constructor() ERC20("SimpleStableCoin", "SSC") Ownable(msg.sender) {}

    /**
     * @dev Burns a specified amount of tokens from the caller's account.
     * Can only be called by the owner of the contract.
     * @param _amount The amount of tokens to burn.
     * @notice The amount must be greater than zero and cannot exceed the caller's balance.
     * @custom:error SSC_MustBeMoreThanZero() If the amount to burn is zero.
     * @custom:error SSC_BurnAmountExceedsBalance() If the burn amount exceeds the caller's balance.
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert SSC_MustBeMoreThanZero();
        }

        if (balance < _amount) {
            revert SSC_BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    /**
     * @dev Mints a specified amount of tokens to a given address.
     * Can only be called by the owner of the contract.
     * @param _to The address to which the minted tokens will be sent.
     * @param _amount The amount of tokens to mint.
     * @notice The address must not be zero, and the amount must be greater than zero.
     * @custom:error SSC_NotZeroAddress() If the recipient address is zero.
     * @custom:error SSC_MustBeMoreThanZero() If the mint amount is zero.
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert SSC_NotZeroAddress();
        }

        if (_amount <= 0) {
            revert SSC_MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
