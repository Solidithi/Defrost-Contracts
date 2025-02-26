// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { LaunchpoolFactory } from "../../src/LaunchpoolFactory.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract CreateLaunchPoolTest is Test {
	LaunchpoolFactory public poolFactory;
	MockERC20 public projectToken;
	MockERC20 public vAsset;
	MockERC20 public nativeAsset;

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
		nativeAsset = new MockERC20("Native Imaginary", "Imaginary");
		poolFactory = new LaunchpoolFactory(address(vAsset), address(nativeAsset));
	}

	function testCreateSinglePool() public {
		// Arrange
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(vAsset);

		address[] memory acceptedNativeAssets = new address[](1);
		acceptedNativeAssets[0] = address(nativeAsset);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);

		// Assert: Check if the pool count increased
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 1, "Pool count is not 1");
		assertTrue(poolIds.length == 1, "Pool id length is not 1");
	}
}
