// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { console } from "forge-std/console.sol";
import { DeployMockXCMOracle } from "../testutils/DeployMockXCMOracle.sol";

contract NativeExchangeRateTest is Test {
	MockLaunchpool launchpool;
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	DeployMockXCMOracle mockOracleDeployer = new DeployMockXCMOracle();
	address owner;

	// Constants for testing
	uint128 public START_BLOCK = 100;
	uint128 public constant END_BLOCK = 1000;
	uint256 public constant MAX_VSTAKER = 1000 ether;

	constructor() {
		// Deploy mock xcm oracle with 1.2 initial rate, 10 block interval, 8% APY, 6 seconds block time
		mockOracleDeployer.deploy(12000, 10, 80000, 6);
	}

	function setUp() public {
		owner = address(this);

		// Deploy mock tokens
		projectToken = new MockERC20("Project Token", "PT");
		vAsset = new MockERC20("vAsset Token", "vToken");
		nativeAsset = new MockERC20("Native Asset", "Native"); // Different decimals to test scaling

		// Set start block in the future to ensure startBlock > current block
		START_BLOCK = uint128(block.number + 10);

		// Deploy mock XCM Oracle

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

	// Test case: Initial exchange rate calculation
	function test_initial_native_ex_rate() public {
		uint256 initialRate = launchpool.NATIVE_SCALING_FACTOR() *
			launchpool.exposed_getTokenByVTokenWithoutFee(
				1 * 10 ** vAsset.decimals()
			);

		// Assert if native exchange rate was intialized in constructor
		assertEq(
			launchpool.lastNativeExRate(),
			initialRate,
			"Initial rate hasn't been initialized correctly in constructor"
		);

		// Same assertion as above but at differnt block
		vm.roll(START_BLOCK + 1);
		assertEq(
			launchpool.lastNativeExRate(),
			initialRate,
			"Initial rate hasn't been initialized correctly in constructor (different block)"
		);
	}

	function test_update_native_ex_rate() public {
		// Set initial conditions
		vm.roll(START_BLOCK + 1);
		launchpool.wild_setTickBlock(START_BLOCK);

		// Both values in wei (18 decimals)
		uint256 currentExRate = launchpool.lastNativeExRate();
		uint256 increasedExRate = (currentExRate * 101) / 100;
		uint256 vTokenAmount = 100 ether;
		uint256 nativeAmount = (100 ether * increasedExRate) /
			launchpool.NATIVE_SCALING_FACTOR();

		// Call the function
		launchpool.wild_updateNativeTokenExchangeRate(
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
		launchpool.wild_updateNativeTokenExchangeRate(
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
		uint256 vAssetAmount = 100 * 10 ** vAsset.decimals();
		uint256 nativeAmount = (vAssetAmount *
			((launchpool.lastNativeExRate() * 102) / 100)) /
			launchpool.NATIVE_SCALING_FACTOR();
		launchpool.wild_updateNativeTokenExchangeRate(
			nativeAmount,
			vAssetAmount
		);
		// Set tick block after first update to mirror contract behaviour
		launchpool.wild_setTickBlock(uint128(firstUpdateBlock));

		uint256 initialRate = launchpool.lastNativeExRate();

		// Move forward to the future
		uint256 secondUpdateBlock = firstUpdateBlock + 15;
		vm.roll(secondUpdateBlock);

		// Second update with different ex-rate
		uint256 newVAssetAmount = vAssetAmount;
		uint256 newNativeAmount = (newVAssetAmount *
			((initialRate * 105) / 100)) / launchpool.NATIVE_SCALING_FACTOR();

		// Calculate expected new rate
		uint256 newRate = (newNativeAmount *
			launchpool.NATIVE_SCALING_FACTOR()) / newVAssetAmount;

		// Calculate expected average gradient
		uint256 rateDelta = newRate - initialRate;
		uint256 blockDelta = secondUpdateBlock - firstUpdateBlock;
		uint256 newGradient = rateDelta / blockDelta;
		uint256 sampleCount = launchpool.nativeExRateSampleCount();
		uint256 expectedAvgGradient = (launchpool.avgNativeExRateGradient() *
			(sampleCount - 1) +
			newGradient) / (sampleCount);

		// Second update
		launchpool.wild_updateNativeTokenExchangeRate(
			newNativeAmount,
			newVAssetAmount
		);
		launchpool.wild_setTickBlock(uint128(secondUpdateBlock));

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
		launchpool.wild_updateNativeTokenExchangeRate(110 ether, 100 ether);

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
			uint256 nativeAmount = (110 ether + i * 1e18);
			uint256 vTokenAmount = 100 ether;

			// Update the exchange rate
			launchpool.wild_updateNativeTokenExchangeRate(
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

			assertApproxEqAbs(
				launchpool.avgNativeExRateGradient(),
				avgGradient,
				1e12,
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
		assertApproxEqAbs(
			launchpool.avgNativeExRateGradient(),
			avgGradient,
			1e12,
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

		vm.roll(START_BLOCK);

		// 1 token6 = 10^6, 1 token18 = 10^18
		uint256 vTokenAmount = 1 * 10 ** token18.decimals(); // 1 token with 18 decimals
		uint256 nativeAmount = (vTokenAmount *
			((testPool.lastNativeExRate() * 1001) / 1000)) /
			testPool.NATIVE_SCALING_FACTOR();

		// Check scaling factor is appropriate for 6 decimals
		assertEq(
			testPool.NATIVE_SCALING_FACTOR(),
			testPool.BASE_PRECISION() / 10 ** token6.decimals(),
			"Incorrect scaling factor for 6-decimal token"
		);

		vm.roll(START_BLOCK + 20);
		testPool.wild_updateNativeTokenExchangeRate(nativeAmount, vTokenAmount);
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
		launchpool.wild_updateNativeTokenExchangeRate(100 ether, 0);
	}

	// ==================== Fuzz Tests ====================

	// Fuzz test for exchange rate calculation with varying inputs
	function test_fuzz_ex_rate_calculation_at_varying_block_num(
		uint256 nativeAmount,
		uint256 vTokenAmount,
		uint256 examineBlock
	) public {
		// Bound inputs to reasonable values to avoid overflow/underflow
		uint256 expectedRate = (launchpool.lastNativeExRate() * 1001) / 1000;
		vTokenAmount = bound(vTokenAmount, 1, 1e36);
		nativeAmount =
			(vTokenAmount * expectedRate) /
			launchpool.NATIVE_SCALING_FACTOR();
		examineBlock = bound(examineBlock, START_BLOCK, END_BLOCK);

		launchpool.wild_setTickBlock(START_BLOCK);
		vm.roll(START_BLOCK + 5);

		launchpool.wild_updateNativeTokenExchangeRate(
			nativeAmount,
			vTokenAmount
		);
		launchpool.wild_setTickBlock(START_BLOCK + 5);

		assertApproxEqAbs(
			launchpool.lastNativeExRate(),
			expectedRate,
			1e12,
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
		initialVToken = bound(initialVToken, 1, 1e30); // Bound relative to initialNative
		initialNative = bound(initialNative, initialVToken, 2e30);
		finalNative = bound(
			finalNative,
			initialNative,
			(initialNative * 110) / 100
		);
		finalVToken = initialVToken;
		blocksDelta = uint64(
			bound(blocksDelta, 1, END_BLOCK - START_BLOCK - 1)
		);

		// Override pools' initial rate
		uint256 poolInitBlock = block.number;
		uint256 initialRate = (initialNative *
			launchpool.NATIVE_SCALING_FACTOR()) / initialVToken;
		launchpool.wild_setLastNativeExRate(initialRate);
		launchpool.wild_setNativeExRateSampleCount(1);
		launchpool.wild_setLastNativeExRateUpdateBlock(uint128(poolInitBlock));

		// // Advance to start block to start staking
		// vm.roll(START_BLOCK);

		// Move forward to block START_BLOCK + blocksDelta
		vm.roll(poolInitBlock + blocksDelta);

		// Set the new exchange rate
		launchpool.wild_updateNativeTokenExchangeRate(finalNative, finalVToken);
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
				"Fuzz: Rate delta calculation mismatch"
			);
		} else {
			revert("Fuzz: Final rate should be greater than initial rate");
		}
	}

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
		launchpool.wild_updateNativeTokenExchangeRate(
			nativeAmount,
			vTokenAmount
		);

		// No assertion needed lol ; D - test passes if no revert
	}

	function test_estimated_native_ex_rate_at_end() public {
		uint256 poolInitBlock = block.number;
		uint256 newRateBlock = START_BLOCK + 20;

		// Get the latest vToken -> token rate from Oracle
		uint256 oldRate = launchpool.lastNativeExRate();

		// Increase the rate by 10%
		uint256 newRate = (oldRate * 110) / 100;

		// Tweak new rate for the pool
		uint256 vAssetAmount = 100 * 10 ** vAsset.decimals();
		uint256 nativeAmount = (vAssetAmount * newRate) /
			launchpool.NATIVE_SCALING_FACTOR();

		vm.roll(newRateBlock);
		launchpool.wild_updateNativeTokenExchangeRate(
			nativeAmount,
			vAssetAmount
		);
		launchpool.wild_setLastNativeExRateUpdateBlock(uint128(newRateBlock));

		// Get the estimated rate at the end
		uint256 rateAtEnd = launchpool.exposed_getEstimatedNativeExRateAtEnd();
		assertTrue(rateAtEnd > newRate, "Rate at end should be higher");

		uint256 gradient = (newRate - oldRate) / (newRateBlock - poolInitBlock);
		uint256 expectedRateAtEnd = newRate +
			(gradient * (END_BLOCK - newRateBlock));
		assertApproxEqAbs(
			rateAtEnd,
			expectedRateAtEnd,
			1e10,
			"Rate at end different from expected"
		);
	}

	// Test that the estimated rate does not change after pool end
	function test_estimated_native_ex_rate_not_change_after_end() public {
		vm.roll(START_BLOCK + 10);

		// Simulate investor stake (manually update native exchange rate)
		uint256 initialRate = launchpool.lastNativeExRate();
		uint256 rateAfterFirstStake = (initialRate * 105) / 100;
		uint256 vAssetAmount = 100 * 10 ** vAsset.decimals();
		uint256 firstStakeNativeAmount = (vAssetAmount * rateAfterFirstStake) /
			launchpool.NATIVE_SCALING_FACTOR();
		launchpool.wild_updateNativeTokenExchangeRate(
			firstStakeNativeAmount,
			vAssetAmount
		);
		launchpool.wild_setTickBlock(START_BLOCK + 10);

		// Check that avg gradient has been updated (greater than 0)
		assertTrue(
			launchpool.avgNativeExRateGradient() > 0,
			"Gradient should be greater than 0 after 1 investor staked"
		);

		// Tweak launchpool native exchange rate
		vm.roll(START_BLOCK + 20);
		uint256 newRate = (initialRate * 110) / 100;
		uint256 newNativeAmount = (vAssetAmount * newRate) /
			launchpool.NATIVE_SCALING_FACTOR();
		launchpool.wild_updateNativeTokenExchangeRate(
			newNativeAmount,
			vAssetAmount
		);
		launchpool.wild_setTickBlock(START_BLOCK + 20);
		uint256 expectedRateAtEnd = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();

		// Move past end block
		vm.roll(END_BLOCK + 10);

		// Try tweaking native exchange rate again and expect it to not update
		uint256 afterEndRate = (initialRate * 110) / 100;
		uint256 afterEndNativeAmount = (vAssetAmount * afterEndRate) /
			launchpool.NATIVE_SCALING_FACTOR();
		uint256 avgGradientBeforeAction = launchpool.avgNativeExRateGradient();
		launchpool.wild_updateNativeTokenExchangeRate(
			afterEndNativeAmount,
			vAssetAmount
		);
		launchpool.wild_setTickBlock(END_BLOCK + 10);
		uint256 avgGradientAfterAction = launchpool.avgNativeExRateGradient();
		assertEq(
			avgGradientAfterAction,
			avgGradientBeforeAction,
			"Avg gradient should not change after pool end if it's gt. than 0"
		);
		assertEq(
			launchpool.exposed_getEstimatedNativeExRateAtEnd(),
			expectedRateAtEnd,
			"Rate at end should not change after pool end if avg gradient is gt. than 0"
		);
		assertEq(
			launchpool.lastNativeExRate(),
			newRate,
			"Last native exchange rate should not change after pool end whatsoever"
		);
	}

	// Test edge case where avg gradient is still 0 after end block (too few investors)
	function test_estimated_native_ex_rate_change_after_end() public {
		uint256 initialNativeExRateUpdateBlock = block.number;

		// Simulate investor stake at first block (should
		// not update anything related to native token exchange rate)
		uint256 initialRate = launchpool.lastNativeExRate();
		uint256 rateAfterFirstStake = (initialRate * 105) / 100;
		uint256 vAssetAmount = 100 * 10 ** vAsset.decimals();
		uint256 firstStakeNativeAmount = (vAssetAmount * rateAfterFirstStake) /
			launchpool.NATIVE_SCALING_FACTOR();
		launchpool.wild_updateNativeTokenExchangeRate(
			firstStakeNativeAmount,
			vAssetAmount
		);

		// Check that avg gradient has not been updated (greater than 0)
		assertEq(
			launchpool.avgNativeExRateGradient(),
			0,
			"Gradient should still be 0 if investor stakes at start block"
		);
		// Check that lastNativeExRate has not been updated
		assertEq(
			launchpool.lastNativeExRate(),
			initialRate,
			"Native exchange rate should not change if investor staked at start block"
		);

		// Move past end block
		vm.roll(END_BLOCK + 10);

		// Try tweaking native exchange rate again and expect pool to accept that number
		uint256 afterEndRate = (initialRate * 110) / 100;
		uint256 afterEndNativeAmount = (vAssetAmount * afterEndRate) /
			launchpool.NATIVE_SCALING_FACTOR();
		launchpool.wild_updateNativeTokenExchangeRate(
			afterEndNativeAmount,
			vAssetAmount
		);
		uint256 expectedAvgGradientAfterAction = (afterEndRate - initialRate) /
			(END_BLOCK + 10 - initialNativeExRateUpdateBlock);
		uint256 avgGradientAfterAction = launchpool.avgNativeExRateGradient();
		uint256 expectedRateAtEnd = initialRate +
			expectedAvgGradientAfterAction *
			(END_BLOCK - initialNativeExRateUpdateBlock);

		assertEq(
			avgGradientAfterAction,
			expectedAvgGradientAfterAction,
			"Avg. gradient should be updated after pool end if it's still 0 by then"
		);
		assertEq(
			launchpool.exposed_getEstimatedNativeExRateAtEnd(),
			expectedRateAtEnd,
			"Rate at end should change when action is invoked after pool while avg. gradient is still 0"
		);
		assertEq(
			launchpool.lastNativeExRate(),
			initialRate,
			"Native exchange should not be updated after pool whatsoever"
		);
	}

	function test_no_state_update_if_rate_dont_change() public {
		uint256 initialRate = launchpool.lastNativeExRate();

		// Legitimate update
		vm.roll(START_BLOCK);
		uint256 newRate = (initialRate * 10001) / 10000;
		uint256 newVAmount = 1 * 10 ** vAsset.decimals();
		uint256 newNativeAmount = (newVAmount * newRate) /
			launchpool.NATIVE_SCALING_FACTOR();
		launchpool.wild_updateNativeTokenExchangeRate(
			newNativeAmount,
			newVAmount
		);

		// Fault update (rate don't change)
		uint256 lastNativeExRate = launchpool.lastNativeExRate();
		uint256 lastNativeExRateUpdateBlock = launchpool
			.lastNativeExRateUpdateBlock();
		uint256 avgNativeExRateGradient = launchpool.avgNativeExRateGradient();
		uint256 poolDurationBlocks = END_BLOCK - START_BLOCK;
		vm.roll(START_BLOCK + ((poolDurationBlocks * 2) / 3));
		launchpool.wild_updateNativeTokenExchangeRate(
			newNativeAmount,
			newVAmount
		);

		// Assert no state update
		assertEq(
			launchpool.lastNativeExRate(),
			lastNativeExRate,
			"Native exchange rate should not change if rate don't change"
		);
		assertEq(
			launchpool.lastNativeExRateUpdateBlock(),
			lastNativeExRateUpdateBlock,
			"Last native exchange rate update block should not change if rate don't change"
		);
		assertEq(
			launchpool.avgNativeExRateGradient(),
			avgNativeExRateGradient,
			"Avg. gradient should not change if rate don't change"
		);
	}
}
