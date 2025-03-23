// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { console } from "forge-std/console.sol";

contract ERC20WithoutDecimals {
	constructor(string memory _name, string memory _symbol) {}
}

contract TokenDecimalsTest is Test {
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
		xcmOracle = new MockXCMOracle(12000, 10, 100);

		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		// Deploy Launchpool with exposed functions
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

	function test_get_token_decimals() public view {
		assertEq(
			launchpool.exposed_getTokenDecimals(address(vAsset)),
			IERC20Metadata(vAsset).decimals(),
			"VAsset decimals mismatch"
		);
		assertEq(
			launchpool.exposed_getTokenDecimals(address(nativeAsset)),
			IERC20Metadata(nativeAsset).decimals(),
			"Native asset decimals mismatch"
		);
		assertEq(
			launchpool.exposed_getTokenDecimals(address(projectToken)),
			IERC20Metadata(projectToken).decimals(),
			"Project token decimals mismatch"
		);
	}

	function test_revert_tokens_dont_have_decimals() public {
		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		// Expect revert when deploying Launchpool with project token without decimals
		ERC20WithoutDecimals fakePToken = new ERC20WithoutDecimals(
			"Fake Project Token",
			"FT"
		);
		vm.expectRevert(
			abi.encodeWithSelector(
				Launchpool.FailedToReadTokenDecimals.selector
			)
		);
		new MockLaunchpool(
			owner,
			address(fakePToken),
			address(vAsset),
			address(nativeAsset),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);

		// Expect revert when deploying Launchpool with native token without decimals
		ERC20WithoutDecimals fakeNativeAsset = new ERC20WithoutDecimals(
			"Fake Native Token",
			"FNT"
		);
		vm.expectRevert(
			abi.encodeWithSelector(
				Launchpool.FailedToReadTokenDecimals.selector
			)
		);
		new MockLaunchpool(
			owner,
			address(projectToken),
			address(vAsset),
			address(fakeNativeAsset),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);
	}
}
