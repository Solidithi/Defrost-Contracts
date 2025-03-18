// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { console } from "forge-std/console.sol";

contract NativeExchangeRateTest is Test {
	MockLaunchpool launchpool;
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	MockXCMOracle xcmOracle;
	address owner;

	// Constants for testing
	uint128 public constant START_BLOCK = 100;
	uint128 public constant END_BLOCK = 1000;
	uint256 public constant MAX_VSTAKER = 1000 ether;

	function setUp() public {
		owner = address(this);

		// Deploy mock tokens
		projectToken = new MockERC20("Project Token", "PT");
		vAsset = new MockERC20("vAsset Token", "vToken");
		nativeAsset = new MockERC20("Native Asset", "Native"); // Different decimals to test scaling

		// Deploy mock XCM Oracle
		xcmOracle = new MockXCMOracle();

		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		// Set block number to ensure startBlock > current block
		vm.roll(START_BLOCK - 10);

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

	// Test case: Initial exchange rate calculation
	function test_initial_ex_rate() public {
		// Set initial conditions
		vm.roll(START_BLOCK + 1);
		launchpool.wild_setTickBlock(START_BLOCK);

		// Both values in wei (18 decimals)
		uint256 nativeAmount = 100 ether;
		uint256 vTokenAmount = 100 ether;

		// Call the function
		launchpool.exposed_updateNativeTokenExchangeRate(
			nativeAmount,
			vTokenAmount
		);

		// Check that lastNativeExRate was set correctly
		uint256 expectedExRate = (nativeAmount *
			launchpool.NATIVE_SCALING_FACTOR()) / vTokenAmount;
		assertEq(
			launchpool.lastNativeExRate(),
			expectedExRate,
			"Initial exchange rate not set correctly"
		);

		// Sample count should still be 0 for first call
		assertEq(
			launchpool.nativeExRateSampleCount(),
			2,
			"Sample count should be 2 after first call"
		);
	}

	// Test case: No update if current block equals tickBlock
	function test_no_update_on_same_block() public {
		uint256 blockNum = START_BLOCK + 10;
		vm.roll(blockNum);

		// Set tickBlock to current block
		launchpool.wild_setTickBlock(uint128(blockNum));

		// Set initial exchange rate
		launchpool.wild_setLastNativeExRate(
			1 * launchpool.NATIVE_SCALING_FACTOR()
		);

		// Call with any values
		launchpool.exposed_updateNativeTokenExchangeRate(
			101 * 10 ** nativeAsset.decimals(),
			102 * 10 ** vAsset.decimals()
		);

		// Exchange rate should remain unchanged
		assertEq(
			launchpool.lastNativeExRate(),
			1 * launchpool.NATIVE_SCALING_FACTOR(),
			"Exchange rate should not change when block == tickBlock"
		);
	}

	// Test case: Gradient calculation between two exchange rate samples
	function test_ex_rate_update() public {
		// Set initial conditions
		uint256 firstUpdateBlock = START_BLOCK + 10;
		vm.roll(firstUpdateBlock);

		// First update to set initial exchange rate
		launchpool.exposed_updateNativeTokenExchangeRate(
			102 * 10 ** nativeAsset.decimals(),
			100 * 10 ** vAsset.decimals()
		);
		// Set tick block after first update to mirror contract behaviour
		launchpool.wild_setTickBlock(uint128(firstUpdateBlock));

		uint256 initialRate = launchpool.lastNativeExRate();

		// Move forward to the future
		uint256 secondUpdateBlock = firstUpdateBlock + 15;
		vm.roll(secondUpdateBlock);

		// Second update with different ex-rate
		uint256 newNativeAmount = 110 * 10 ** nativeAsset.decimals();
		uint256 newVTokenAmount = 100 * 10 ** vAsset.decimals();

		// Calculate expected new rate
		uint256 newRate = (newNativeAmount *
			launchpool.NATIVE_SCALING_FACTOR()) / newVTokenAmount;

		// Calculate expected average gradient
		uint256 rateDelta = newRate - initialRate;
		uint256 blockDelta = secondUpdateBlock - firstUpdateBlock;
		uint256 newGradient = rateDelta / blockDelta;
		uint256 sampleCount = launchpool.nativeExRateSampleCount();
		uint256 expectedAvgGradient = (launchpool.avgNativeExRateGradient() *
			sampleCount +
			newGradient) / (sampleCount + 1);

		// Second update
		launchpool.exposed_updateNativeTokenExchangeRate(
			newNativeAmount,
			newVTokenAmount
		);

		// 512666666666

		// Check exchange rate was updated
		assertEq(
			launchpool.lastNativeExRate(),
			newRate,
			"Native token ex-rate not updated correctly"
		);

		// Check gradient calculation
		assertEq(
			launchpool.avgNativeExRateGradient(),
			expectedAvgGradient,
			"Average native ex-rate gradient not calculated correctly"
		);

		// Sample count should be 1 now
		assertEq(
			launchpool.nativeExRateSampleCount(),
			sampleCount + 1,
			"Sample count should increase by 1 after update"
		);
	}

	// Test case: Rolling average gradient calculation
	function test_multiple_rolling_average_gradient_updates() public {
		// First, set initial exchange rate and reset pool pool states to de-effect the constructor
		uint256 initialRate = (105 * launchpool.NATIVE_SCALING_FACTOR()) / 100;
		launchpool.wild_setLastNativeExRate(initialRate);
		launchpool.wild_setNativeExRateSampleCount(1);
		launchpool.wild_setTickBlock(START_BLOCK);
		// launchpool.exposed_updateNativeTokenExchangeRate(100 ether, 100 ether);

		// Move forward
		vm.roll(START_BLOCK + 15);

		// Second update
		launchpool.exposed_updateNativeTokenExchangeRate(110 ether, 100 ether);

		// Set sample count manually to test rolling average
		launchpool.wild_setNativeExRateSampleCount(5);
		launchpool.wild_setAvgNativeExRateGradient(2 ether); // 2 tokens per block

		// Store initial values for verification
		uint256 avgGradient = 2 ether;
		uint256 sampleCount = 5;
		uint256 lastRate = (110 * launchpool.NATIVE_SCALING_FACTOR()) / 100;
		uint256 lastBlock = START_BLOCK + 15;

		// Run multiple rolling average updates through a loop
		uint256 numUpdates = 15; // Number of updates to perform

		for (uint256 i = 1; i <= numUpdates; i++) {
			// Move forward by a variable number of blocks (3-7 blocks)
			uint256 blockJump = 3 + (i % 5);
			uint256 currentBlock = lastBlock + blockJump;
			vm.roll(currentBlock);

			// Calculate next exchange rate with a variable rate increase
			uint256 nativeAmount = 110 ether + i;
			uint256 vTokenAmount = 100 ether;

			// Update the exchange rate
			launchpool.exposed_updateNativeTokenExchangeRate(
				nativeAmount,
				vTokenAmount
			);

			// Calculate the expected gradient and rolling average
			uint256 newRate = (nativeAmount *
				launchpool.NATIVE_SCALING_FACTOR()) / vTokenAmount;
			uint256 rateDelta = newRate - lastRate;
			uint256 blockDelta = currentBlock - lastBlock;
			uint256 newGradient = rateDelta / blockDelta;

			// Update expected rolling average: (oldAvg * oldCount + newSample) / (oldCount + 1)
			avgGradient =
				(avgGradient * (sampleCount - 1) + newGradient) /
				(sampleCount);
			sampleCount++;

			// Update values for next iteration
			lastRate = newRate;
			lastBlock = currentBlock;

			assertEq(
				launchpool.avgNativeExRateGradient(),
				avgGradient,
				string(
					abi.encodePacked(
						"Rolling average gradient incorrect at update ",
						i
					)
				)
			);

			assertEq(
				launchpool.nativeExRateSampleCount(),
				sampleCount,
				string(abi.encodePacked("Sample count incorrect at update ", i))
			);
		}

		// Final verification
		assertEq(
			launchpool.avgNativeExRateGradient(),
			avgGradient,
			// 2, // Small tolerance for division rounding
			"Final rolling average gradient calculation incorrect"
		);

		assertEq(
			launchpool.nativeExRateSampleCount(),
			5 + numUpdates,
			"Final sample count incorrect"
		);
	}

	// Test case: Edge case with different token decimals (unlikely in practice)
	function test_different_token_decimals() public {
		// Create tokens with different decimals
		MockERC20 token6 = new MockERC20("6 Decimals", "T6");
		token6.setDecimals(6);
		MockERC20 token18 = new MockERC20("18 Decimals", "T18");
		token18.setDecimals(18);

		// Deploy new launchpool with these tokens
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		vm.roll(START_BLOCK - 10);

		MockLaunchpool testPool = new MockLaunchpool(
			owner,
			address(projectToken),
			address(token18), // vAsset with 18 decimals
			address(token6), // Native asset with 6 decimals
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);

		// Test exchange rate calculation
		vm.roll(START_BLOCK);
		testPool.wild_setTickBlock(START_BLOCK);

		// 1 token6 = 10^6, 1 token18 = 10^18
		uint256 nativeAmount = 1 * 10 ** token6.decimals(); // 1 token with 6 decimals
		uint256 vTokenAmount = 1 * 10 ** token18.decimals(); // 1 token with 18 decimals

		// Check scaling factor is appropriate for 6 decimals
		assertEq(
			testPool.NATIVE_SCALING_FACTOR(),
			testPool.BASE_PRECISION() / 10 ** token6.decimals(),
			"Incorrect scaling factor for 6-decimal token"
		);

		vm.roll(START_BLOCK + 20);
		testPool.exposed_updateNativeTokenExchangeRate(
			nativeAmount,
			vTokenAmount
		);
		// Check exchange rate calculation with different decimals
		uint256 expectedRate = (nativeAmount *
			testPool.NATIVE_SCALING_FACTOR()) / vTokenAmount;
		assertEq(
			testPool.lastNativeExRate(),
			expectedRate,
			"Exchange rate calculation wrong with different decimals"
		);
	}

	// Test case: Zero division protection
	function test_zero_division_protection() public {
		vm.roll(START_BLOCK + 10);
		launchpool.wild_setTickBlock(START_BLOCK);

		// Try with zero vTokenAmount
		vm.expectRevert(); // Should revert on division by zero
		launchpool.exposed_updateNativeTokenExchangeRate(100 ether, 0);
	}

	// ==================== Fuzz Tests ====================

	// Fuzz test for exchange rate calculation with varying inputs
	function test_fuzz_ex_rate_calculation_at_varying_block_num(
		uint256 nativeAmount,
		uint256 vTokenAmount,
		uint256 examineBlock
	) public {
		// Bound inputs to reasonable values to avoid overflow/underflow
		nativeAmount = bound(nativeAmount, 1, 1e36);
		vTokenAmount = bound(vTokenAmount, 1, 1e36);
		examineBlock = bound(examineBlock, START_BLOCK, END_BLOCK);

		vm.roll(START_BLOCK + 10);
		launchpool.wild_setTickBlock(START_BLOCK);

		launchpool.exposed_updateNativeTokenExchangeRate(
			nativeAmount,
			vTokenAmount
		);

		uint256 expectedRate = (nativeAmount *
			launchpool.NATIVE_SCALING_FACTOR()) / vTokenAmount;
		assertEq(
			launchpool.lastNativeExRate(),
			expectedRate,
			"Fuzz: Exchange rate calculation failed"
		);
	}

	// Fuzz test for gradient calculation with varying exchange rates
	function test_fuzz_gradient_calculation(
		uint256 initialNative,
		uint256 initialVToken,
		uint256 finalNative,
		uint256 finalVToken,
		uint64 blocksDelta
	) public {
		// Bound inputs to reasonable values
		initialNative = bound(initialNative, 1, 1e30);
		initialVToken = bound(initialVToken, 1, initialNative); // Bound relative to initialNative
		finalNative = bound(
			finalNative,
			initialNative,
			(initialNative * 110) / 100
		);
		finalVToken = initialVToken; // Reality: it should be like this
		blocksDelta = uint64(
			bound(blocksDelta, 1, END_BLOCK - START_BLOCK - 1)
		);

		// Reset pool for custom fresh start
		launchpool.wild_setTickBlock(START_BLOCK);
		vm.roll(START_BLOCK);

		uint256 initialRate = (initialNative *
			launchpool.NATIVE_SCALING_FACTOR()) / initialVToken;
		launchpool.wild_setLastNativeExRate(initialRate);
		launchpool.wild_setNativeExRateSampleCount(1);
		// launchpool.exposed_updateNativeTokenExchangeRate(
		// 	initialNative,
		// 	initialVToken
		// );
		// Set tickBlock after first update to mirror contract behaviour
		// uint256 initialRate = launchpool.lastNativeExRate();

		// Move forward by blocksDelta
		vm.roll(START_BLOCK + blocksDelta);

		// Set the new exchange rate
		launchpool.exposed_updateNativeTokenExchangeRate(
			finalNative,
			finalVToken
		);
		// Set tick block after second update to mirror contract behaviour
		launchpool.wild_setTickBlock(START_BLOCK + blocksDelta);
		uint256 finalRate = launchpool.lastNativeExRate();

		// Calculate expected gradient
		uint256 rateDelta;
		if (finalRate >= initialRate) {
			rateDelta = finalRate - initialRate;
			uint256 expectedAvgGradient = rateDelta / blocksDelta;

			assertApproxEqAbs(
				launchpool.avgNativeExRateGradient(),
				expectedAvgGradient,
				10, // Small tolerance due to division rounding
				"Fuzz: Rate delta calculation failed"
			);
		} else {
			revert("Fuzz: Final rate should be greater than initial rate");
		}
	}

	// Fuzz test for rolling average calculation
	// function test_fuzz_reverse_engineer_average_gradient_calculation(
	// 	uint256 oldGradient,
	// 	uint8 sampleCount,
	// 	uint256 newGradient
	// ) public {
	// 	// Use smaller bounds to prevent overflow
	// 	sampleCount = uint8(bound(sampleCount, 1, 100));
	// 	oldGradient = bound(oldGradient, 1, 10 * 10 ** nativeAsset.decimals());
	// 	newGradient = bound(newGradient, 1, oldGradient);

	// 	// Set initial values
	// 	launchpool.wild_setAvgNativeExRateGradient(oldGradient);
	// 	launchpool.wild_setNativeExRateSampleCount(sampleCount);

	// 	// Setup initial block and rate
	// 	uint256 initialBlock = START_BLOCK + 10;
	// 	vm.roll(initialBlock);
	// 	uint256 oldRate = (80 * launchpool.NATIVE_SCALING_FACTOR()) / 100;
	// 	launchpool.wild_setTickBlock(uint128(initialBlock));
	// 	launchpool.wild_setLastNativeExRate(oldRate);

	// 	// Move forward by blockDelta blocks
	// 	uint256 blockDelta = 10;
	// 	uint256 newBlock = initialBlock + blockDelta;
	// 	vm.roll(newBlock);

	// 	// Calculate new rate WITHOUT potential overflow
	// 	uint256 rateDelta = bound(newGradient * blockDelta, 0, 1e20);
	// 	vm.assume(oldRate > rateDelta);
	// 	uint256 newRate = oldRate - rateDelta;

	// 	// Use inverse version of the ACTUAL formula from the contract to calc. nativeAmount
	// 	uint256 nativeAmount = 1 * 10 ** nativeAsset.decimals();
	// 	uint256 vTokenAmount = (nativeAmount *
	// 		launchpool.NATIVE_SCALING_FACTOR()) / newRate;

	// 	// Call the function
	// 	launchpool.exposed_updateNativeTokenExchangeRate(
	// 		nativeAmount,
	// 		vTokenAmount
	// 	);

	// 	// Calculate expected average with the same formula as contract
	// 	uint256 expectedAvg = (oldGradient *
	// 		uint256(sampleCount) +
	// 		newGradient) / (uint256(sampleCount) + 1);

	// 	// Use larger tolerance to account for division imprecision
	// 	assertApproxEqAbs(
	// 		launchpool.avgNativeExRateGradient(),
	// 		expectedAvg,
	// 		1e4, // 0.00000000001% arithmetic slippage tolerance
	// 		"Fuzz: Rolling average calculation failed"
	// 	);
	// }

	// Additional fuzz test to ensure no overflow/underflow with extreme values
	function test_fuzz_no_overflow_underflow(
		uint256 nativeAmount,
		uint256 vTokenAmount
	) public {
		// Ensure non-zero vTokenAmount
		nativeAmount = bound(vTokenAmount, 1, 1e36);
		vTokenAmount = bound(vTokenAmount, 1, 1e36);

		// Set up for exchange rate calculation
		vm.roll(START_BLOCK + 10);
		launchpool.wild_setTickBlock(START_BLOCK);

		// This should execute without overflow/underflow
		launchpool.exposed_updateNativeTokenExchangeRate(
			nativeAmount,
			vTokenAmount
		);

		// No assertion needed lol ; D - test passes if no revert
	}

	function test_estimated_native_ex_rate_at_end() public {
		uint256 skipBlocks = END_BLOCK - START_BLOCK - 10;
		vm.roll(START_BLOCK + skipBlocks);

		// Get the latest vToken -> token rate from Oracle
		uint256 oldRate = launchpool.lastNativeExRate();

		// Increase the rate by 10%
		uint256 newRate = (oldRate * 110) / 100;
		assertTrue(newRate > oldRate, "New rate should be higher");

		// Tweak new rate for the pool
		uint256 vAssetAmount = 100 * 10 ** vAsset.decimals();
		uint256 nativeAmount = (vAssetAmount * newRate) /
			launchpool.NATIVE_SCALING_FACTOR();

		launchpool.exposed_updateNativeTokenExchangeRate(
			nativeAmount,
			vAssetAmount
		);
		launchpool.wild_setTickBlock(uint128(START_BLOCK + skipBlocks));

		// Get the estimated rate at the end
		uint256 rateAtEnd = launchpool.exposed_getEstimatedNativeExRateAtEnd();
		assertTrue(rateAtEnd > newRate, "Rate at end should be higher");

		uint256 gradient = (newRate - oldRate) / skipBlocks;
		uint256 expectedRateAtEnd = newRate +
			(gradient * (END_BLOCK - (START_BLOCK + skipBlocks)));
		console.log("Expected rate at end: ", expectedRateAtEnd);
		assertEq(rateAtEnd, expectedRateAtEnd, "Rate at end not as expected");
	}

	// function test_fuzz_gradient_calculation_2(
	// 	uint256 oldGradient,
	// 	uint8 sampleCount,
	// 	uint256 nativeAmount,
	// 	uint256 vTokenAmount
	// ) public {
	// 	// Bound values to prevent overflow
	// 	oldGradient = bound(oldGradient, 1, 1e20);
	// 	sampleCount = uint8(bound(sampleCount, 1, 100));

	// 	// Set up initial state
	// 	launchpool.wild_setAvgNativeExRateGradient(oldGradient);
	// 	launchpool.wild_setNativeExRateSampleCount(sampleCount);

	// 	// Set up initial rate and block
	// 	uint256 initialBlock = START_BLOCK + 10;
	// 	vm.roll(initialBlock);
	// 	uint256 oldRate = 1e20; // Much lower starting rate
	// 	launchpool.wild_setLastNativeExRate(oldRate);
	// 	launchpool.wild_setTickBlock(uint128(initialBlock));

	// 	// Calculate the maximum vTokenAmount that ensures newRate > oldRate
	// 	nativeAmount = bound(nativeAmount, 1e18, 1e30);
	// 	uint256 maxVToken = (nativeAmount *
	// 		launchpool.NATIVE_SCALING_FACTOR()) / (oldRate + 1);

	// 	// Skip if impossible to create a higher rate
	// 	// if (maxVToken < 1e18) return;

	// 	// Set vTokenAmount to ensure new rate is greater than old rate
	// 	vTokenAmount = bound(vTokenAmount, 1e18, maxVToken);

	// 	// Calculate what the new rate WILL be based on these inputs
	// 	uint256 newRate = (nativeAmount * launchpool.NATIVE_SCALING_FACTOR()) /
	// 		vTokenAmount;

	// 	// Move forward
	// 	uint256 blockDelta = 10;
	// 	vm.roll(initialBlock + blockDelta);

	// 	// Calculate expected values
	// 	uint256 rateDelta = newRate - oldRate; // Guaranteed to be positive
	// 	uint256 expectedGradient = rateDelta / blockDelta;
	// 	uint256 expectedAvg = (oldGradient *
	// 		uint256(sampleCount) +
	// 		expectedGradient) / (uint256(sampleCount) + 1);

	// 	// Call function
	// 	launchpool.exposed_updateNativeTokenExchangeRate(
	// 		nativeAmount,
	// 		vTokenAmount
	// 	);

	// 	// Verify result
	// 	assertApproxEqRel(
	// 		launchpool.avgNativeExRateGradient(),
	// 		expectedAvg,
	// 		1e2, // 0.0000000000001% tolerance
	// 		"Gradient calculation incorrect"
	// 	);
	// }
}
