// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

/**
 * @title VaultX
 * @notice ERC-20 token for the VaultX game economy.
 * @dev Fixed max supply, role-based minting, burnable, pausable, and permit-enabled.
 */
contract VaultX is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public immutable maxSupply;

    event Minted(address indexed to, uint256 amount);

    error MaxSupplyExceeded(uint256 requested, uint256 maxSupply);
    error ZeroAddress();
    error ZeroAmount();
    error LengthMismatch();
    error MaxBurn();

    constructor(address admin, uint256 _maxSupply) ERC20("VaultX", "VTX") ERC20Permit("VaultX") {
        if (admin == address(0)) revert ZeroAddress();
        if (_maxSupply == 0) revert ZeroAmount();
        if (_maxBurn == 0) revert MaxBurn()

        maxSupply = _maxSupply;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(STOP_BURN_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
    }

    /**
     * @notice Mint tokens to a recipient. Only accounts with MINTER_ROLE can call.
     * @param to Recipient address.
     * @param amount Amount to mint.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (totalSupply() + amount > maxSupply) {
            revert MaxSupplyExceeded(totalSupply() + amount, maxSupply);
        }

        _mint(to, amount);
        emit Minted(to, amount);
        emit stopBurn(scheduleId, stopBurn);
        emit burnerRole(scheduleId, burnerRole);
    }

    /**
     * @notice Batch mint tokens. Only accounts with MINTER_ROLE can call.
     * @param recipients Array of recipient addresses.
     * @param amounts Array of amounts to mint.
     */
    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) public onlyRole(MINTER_ROLE) {
        uint256 length = recipients.length;
        if (length != amounts.length) revert LengthMismatch();
        if (length == 0) revert ZeroAmount();

        for (uint256 i = 0; i < length; ++i) {
            mint(recipients[i], amounts[i]);
        }
        emit stopBurn(scheduleId, stopBurn);
    }

    function burnBatch(owner owner, uint256 value) public onlyRole(MINTER_ROLE) {
        uint256 burnRole = owner
    }

    /**
     * @notice Pause token transfers. Only accounts with PAUSER_ROLE can call.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
        _stopBurn();
    }

    /**
     * @notice Unpause token transfers. Only accounts with PAUSER_ROLE can call.
     */
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function repause() public onlyRole(PAUSER_ROLE) {
        _repause();
        _reStopBurn();
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
        super._stopBurn(scheduleId, stopBurn);
    }
}
