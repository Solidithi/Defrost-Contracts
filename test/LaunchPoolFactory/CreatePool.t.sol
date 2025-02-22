// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { LaunchPoolFactory } from "../../src/LaunchPoolFactory.sol";
import { LaunchPool } from "../../src/LaunchPool.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

// @todo: Improve testcase later on when implementation for valid vAsset
contract CreateLaunchPoolTest is Test {
	LaunchPoolFactory public poolFactory;
	LaunchPool public launchPool;

	function setUp() public {
		poolFactory = new LaunchPoolFactory();
	}

	function testCreatePool() public {
		// Act: Call createPool function
		uint128[] memory changedBlock = new uint128[](2);
		uint256[] memory emissionRate = new uint256[](2);

		changedBlock[0] = 0;
		changedBlock[1] = 300;

		emissionRate[0] = 5;
		emissionRate[1] = 10;

		uint256 poolId = poolFactory.createPool(
			address(this),
			address(this),
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);

		// Assert: Check if the pool count increased
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 1, "Pool count is not 1");

		// Assert: Check if the pool id return the pool address
		address poolAddress = poolFactory.pools(poolId);
		assertTrue(poolAddress != address(0), "Pool address is 0");

		// Assert: Check if the pool address is valid
		assertTrue(poolFactory.isPoolValid(poolAddress), "Pool is not valid");
	}

	function testCreatePoolWithInvalidProjectToken() public {
		// Act: Call createPool function with invalid project token
		// Assert: Expect revert
		vm.expectRevert(LaunchPool.InvalidAcceptedVAssetAddress.selector);
		uint256 poolId = poolFactory.createPool(
			address(0),
			address(this),
			1000,
			2000,
			1000,
			new uint128[](2),
			new uint256[](2)
		);

		// Assert: Check if the current pool count is 0
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(
			currentPoolId == 0,
			"Pool created with invalid project token"
		);

		// Assert: Check if the pool id value is 0
		assertTrue(poolId == 0, "Pool id is not 0");
	}

	function testCreateSeveralPools() public {
		// Act: Call createPool function several times
		uint128[] memory changedBlock = new uint128[](2);
		uint256[] memory emissionRate = new uint256[](2);

		changedBlock[0] = 0;
		changedBlock[1] = 300;

		emissionRate[0] = 5;
		emissionRate[1] = 10;

		uint256 poolId1 = poolFactory.createPool(
			address(this),
			address(this),
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);
		uint256 poolId2 = poolFactory.createPool(
			address(this),
			address(this),
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);
		uint256 poolId3 = poolFactory.createPool(
			address(this),
			address(this),
			1000,
			2000,
			1000,
			changedBlock,
			emissionRate
		);
		uint256 poolId4 = poolFactory.createPool(
			address(this),
			address(this),
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
			poolId1 == 1 && poolId2 == 2 && poolId3 == 3 && poolId4 == 4,
			"Pool id is not 1"
		);
	}
}
