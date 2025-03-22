// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";

import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract ModifiersTest is Test {
	MockLaunchpool launchpool;
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	MockXCMOracle xcmOracle;
	address owner;

	// Constants for testing
	uint128 public START_BLOCK = 100;
	uint128 public constant END_BLOCK = 1000;
	uint256 public constant MAX_VSTAKER = 1000 ether;

	function setUp() public {
		owner = address(this);

		// Deploy mock tokens
		projectToken = new MockERC20("Project Token", "PT");
		vAsset = new MockERC20("vAsset Token", "vToken");
		nativeAsset = new MockERC20("Native Asset", "Native"); // Different decimals to test scaling

		// Set start block in the future to ensure startBlock > current block
		START_BLOCK = uint128(block.number + 10);

		// Deploy mock XCM Oracle
		xcmOracle = new MockXCMOracle();

		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		launchpool = new MockLaunchpool(
			owner,
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);

		// Mint tokens for testing
		projectToken.freeMintTo(address(launchpool), 1000 ether);
		vAsset.freeMintTo(address(this), 1000 ether);
		nativeAsset.freeMintTo(address(this), 1000 ether);

		// Approve tokens for the launchpool
		vAsset.approve(address(launchpool), type(uint256).max);
		nativeAsset.approve(address(launchpool), type(uint256).max);
	}

	function test_revert_stake_pool_not_active() public {
		// Attempt staking before pool starts
		vm.roll(START_BLOCK - 1);
		vm.expectRevert(
			abi.encodeWithSelector(Launchpool.MustBeDuringPoolTime.selector)
		);
		launchpool.stake(MAX_VSTAKER);

		// Attempt staking after pool ends
		vm.roll(END_BLOCK + 1);
		vm.expectRevert(
			abi.encodeWithSelector(Launchpool.MustBeDuringPoolTime.selector)
		);
		launchpool.stake(MAX_VSTAKER);
	}

	function test_revert_constructor_token_is_zero_address() public {
		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		// Attempt to deploy launchpool with zero address for project token
		vm.expectRevert(
			abi.encodeWithSelector(Launchpool.ZeroAddress.selector)
		);
		new MockLaunchpool(
			owner,
			address(0),
			address(vAsset),
			address(nativeAsset),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);

		// Attempt to deploy launchpool with zero address for vAsset
		vm.expectRevert(
			abi.encodeWithSelector(Launchpool.ZeroAddress.selector)
		);
		new MockLaunchpool(
			owner,
			address(projectToken),
			address(0),
			address(nativeAsset),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);

		// Attempt to deploy launchpool with zero address for native asset
		vm.expectRevert(
			abi.encodeWithSelector(Launchpool.ZeroAddress.selector)
		);
		new MockLaunchpool(
			owner,
			address(projectToken),
			address(vAsset),
			address(0),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);
	}
}
