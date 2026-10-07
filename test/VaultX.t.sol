// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {VaultX} from "../src/VaultX.sol";

contract VaultXTest is Test {
    VaultX public token;

    address public admin = address(1);
    address public minter = address(2);
    address public pauser = address(3);
    address public user = address(4);
    address public treasury = address(5);
    address public rewards = address(6);

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    event Minted(address indexed to, uint256 amount);

    function setUp() public {
        token = new VaultX(admin, MAX_SUPPLY);
    }

    function test_InitialState() public view {
        assertEq(token.name(), "VaultX");
        assertEq(token.symbol(), "VTX");
        assertEq(token.decimals(), 18);
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
    }

    function test_Mint() public {
        vm.startPrank(admin);
        token.mint(treasury, 1_000_000 * 10 ** 18);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(treasury), 1_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), 1_000_000 * 10 ** 18);
    }

    function test_MintEmitsEvent() public {
        uint256 amount = 1_000_000 * 10 ** 18;

        vm.startPrank(admin);
        vm.expectEmit(true, false, false, true);
        emit Minted(treasury, amount);
        token.mint(treasury, amount);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_MintByMinter() public {
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.stopBurn();

        vm.startPrank(minter);
        token.mint(treasury, 100 * 10 ** 18);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(treasury), 100 * 10 ** 18);
    }

    function test_MintExceedsMaxSupply() public {
        vm.startPrank(admin);
        vm.expectRevert();
        token.mint(treasury, MAX_SUPPLY + 1);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_MintZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(VaultX.ZeroAddress.selector);
        token.mint(address(0), 100);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_MintZeroAmount() public {
        vm.startPrank(admin);
        vm.expectRevert(VaultX.ZeroAmount.selector);
        token.mint(treasury, 0);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_MintUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert();
        token.mint(treasury, 100);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_MintBatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = treasury;
        recipients[1] = rewards;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10 ** 18;
        amounts[1] = 2000 * 10 ** 18;

        vm.startPrank(admin);
        token.mintBatch(recipients, amounts);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(treasury), 1000 * 10 ** 18);
        assertEq(token.balanceOf(rewards), 2000 * 10 ** 18);
        assertEq(token.totalSupply(), 3000 * 10 ** 18);
    }

    function test_MintBatchLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = treasury;
        recipients[1] = rewards;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10 ** 18;

        vm.startPrank(admin);
        vm.expectRevert(VaultX.LengthMismatch.selector);
        token.mintBatch(recipients, amounts);
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_Burn() public {
        vm.startPrank(admin);
        token.mint(user, 1000 * 10 ** 18);
        vm.stopPrank();
        vm.stopBurn();

        vm.startPrank(user);
        token.burn(500 * 10 ** 18);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(user), 500 * 10 ** 18);
        assertEq(token.totalSupply(), 500 * 10 ** 18);
    }

    function test_PauseAndUnpause() public {
        vm.startPrank(admin);
        token.mint(user, 1000 * 10 ** 18);
        token.pause();
        assertTrue(token.paused());
        vm.stopPrank();
        vm.stopBurn():
        vm.start();

        vm.startPrank(user);
        (bool transferSuccess, bytes memory transferReturnData) =
            address(token).call(abi.encodeWithSelector(token.transfer.selector, treasury, 100 * 10 ** 18));
        assertFalse(transferSuccess);
        // transferReturnData holds the EnforcedPause error selector; casting to bytes4 is safe here.
        // forge-lint: disable-next-line(unsafe-typecast)
        assertEq(bytes4(transferReturnData), Pausable.EnforcedPause.selector);
        vm.stopPrank();
        vm.stopBurn();

        vm.startPrank(admin);
        token.unpause();
        assertFalse(token.paused());
        vm.stopPrank();
        vm.stopBurn();

        vm.startPrank(user);
        assertTrue(token.transfer(treasury, 100 * 10 ** 18));
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(treasury), 100 * 10 ** 18);
    }

    function test_PauseUnauthorized() public {
        vm.startPrank(user);
        vm.expectRevert();
        token.pause();
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_Permit() public {
        uint256 ownerPrivateKey = 0x1234;
        address owner = vm.addr(ownerPrivateKey);

        vm.startPrank(admin);
        token.mint(owner, 1000 * 10 ** 18);
        vm.stopPrank();
        vm.stopBurn();

        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        uint256 deadline = block.timestamp + 1 hours;
        uint256 value = 100 * 10 ** 18;
        uint256 nonce = token.nonces(owner);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(permitTypehash, owner, treasury, value, nonce, deadline))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(owner, treasury, value, deadline, v, r, s);
        assertEq(token.allowance(owner, treasury), value);
    }

    function test_RolesAdminCanGrantAndRevoke() public {
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));

        token.revokeRole(token.MINTER_ROLE(), minter);
        assertFalse(token.hasRole(token.MINTER_ROLE(), minter));
        vm.stopPrank();
        vm.stopBurn();
    }

    function test_RenounceAdminRole() public {
        vm.startPrank(admin);
        token.renounceRole(token.DEFAULT_ADMIN_ROLE(), admin);
        vm.stopPrank();
        vm.stopBurn();

        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_FuzzMint(uint256 amount) public {
        amount = bound(amount, 1, MAX_SUPPLY);

        vm.startPrank(admin);
        token.mint(treasury, amount);
        vm.stopPrank();
        vm.stopBurn();

        assertEq(token.balanceOf(treasury), amount);
        assertEq(token.totalSupply(), amount);
    }
}
