// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { LaunchpoolFactory } from "../../src/LaunchpoolFactory.sol";
import { Launchpool } from "../../src/Launchpool.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

// @todo: Improve testcase later on when implementation for valid vAsset
contract CreateLaunchPoolTest is Test {
	LaunchpoolFactory public poolFactory;
	Launchpool public launchPool;

	function setUp() public {
		poolFactory = new LaunchpoolFactory();
	}

	function testCreateSinglePool() public {
		// Arrange
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(this);

		uint128[] memory changedBlock = new uint128[](2);
		uint256[] memory emissionRate = new uint256[](2);

		changedBlock[0] = 0;
		changedBlock[1] = 300;

		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(this),
			acceptedVAssets,
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);

		// Assert: Check if the pool count increased
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 1, "Pool count is not 1");
		assertTrue(poolIds.length == 1, "Pool id length is not 1");

		// Assert: Check if the pool id return the pool address
		address poolAddress = poolFactory.getPoolAddress(poolIds[0]);
		assertTrue(poolAddress != address(0), "Pool address is 0");

		// Assert: Check if the pool address is valid
		assertTrue(poolFactory.isPoolValid(poolAddress), "Pool is not valid");
	}

	function testCreatePoolWithInvalidProjectToken() public {
		// Arrange
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(this);

		// Act & Assert: Expect revert
		vm.expectRevert(Launchpool.InvalidAcceptedVAssetAddress.selector);
		poolFactory.createPools(
			address(0),
			acceptedVAssets,
			1000,
			2000,
			1000,
			new uint128[](2),
			new uint256[](2)
		);

		// Assert: Check if the current pool count is 0
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertEq(currentPoolId, 0, "Pool created with invalid project token");
	}

	function testCreateSeveralPoolSeparately() public {
		// Arrange
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(this);

		// Act: Call createPool function several times
		uint128[] memory changedBlock = new uint128[](2);
		uint256[] memory emissionRate = new uint256[](2);

		changedBlock[0] = 0;
		changedBlock[1] = 300;

		emissionRate[0] = 5;
		emissionRate[1] = 10;

		uint256[] memory poolId1s = poolFactory.createPools(
			address(this),
			acceptedVAssets,
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);
		uint256[] memory poolId2s = poolFactory.createPools(
			address(this),
			acceptedVAssets,
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);
		uint256[] memory poolId3s = poolFactory.createPools(
			address(this),
			acceptedVAssets,
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);
		uint256[] memory poolId4s = poolFactory.createPools(
			address(this),
			acceptedVAssets,
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);

		// Assert: Check if the current pool count is 4
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 4, "Pool count is not 4");

		// Assert: Check if the pool id increase sequentially
		assertTrue(
			poolId1s[0] == 1 &&
				poolId2s[0] == 2 &&
				poolId3s[0] == 3 &&
				poolId4s[0] == 4,
			"Pool id is not 1"
		);
	}
}
