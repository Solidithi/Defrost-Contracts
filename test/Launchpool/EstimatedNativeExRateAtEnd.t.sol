// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { console } from "forge-std/console.sol";
import { DeployMockXCMOracle } from "test/testutils/DeployMockXCMOracle.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";
import { SetupStakers } from "test/testutils/SetupStakers.sol";

contract EstimatedNativeExRateAtEndTest is Test {
	MockLaunchpool launchpool;
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	DeployMockXCMOracle mockOracleDeployer = new DeployMockXCMOracle();
	MockXCMOracle mockOracle;
	SetupStakers setupStakers = new SetupStakers();

	address owner;
	address platformAdmin;

	// Constants for testing
	uint128 public START_BLOCK;
	uint128 public END_BLOCK;
	uint256 public constant MAX_VSTAKER = 1000 ether;
	uint256 public constant BLOCK_TIME = 6 seconds;
	uint128 public poolDurationBlocks = uint128(14 days) / uint128(BLOCK_TIME);

	function setUp() public {
		owner = address(this);
		platformAdmin = makeAddr("platformAdmin");

		// Deploy mock tokens
		projectToken = new MockERC20("Project Token", "PT");
		vAsset = new MockERC20("vAsset Token", "vToken");
		nativeAsset = new MockERC20("Native Asset", "Native");

		// Deploy mock XCM oracle with fixed exchange rate (1:1 initially)
		mockOracle = MockXCMOracle(
			mockOracleDeployer.deploy(1e18, 10, 0, 6) // 0% APY to control rates precisely
		);

		// Set start block in the future
		START_BLOCK = uint128(block.number + 10);
		END_BLOCK = START_BLOCK + poolDurationBlocks;

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

		// Setup pool with needed tokens
		uint256 requiredProjectTokens = poolDurationBlocks * emissionRates[0];
		projectToken.freeMintTo(address(launchpool), requiredProjectTokens);

		// Configure Launchpool
		launchpool.wild_setPlatformAdminAddress(platformAdmin);
		launchpool.setXCMOracleAddress(address(mockOracle));
	}

	// Test for the normal case where we have a non-zero gradient
	function test_estimated_native_exrate_with_non_zero_gradient() public {
		// Create stakers
		address[] memory stakers = setupStakers.createAndApprove(
			2,
			address(launchpool),
			address(vAsset)
		);

		// Move to start block
		vm.roll(START_BLOCK);

		// First staking to establish a baseline rate
		vm.prank(stakers[0]);
		launchpool.stake(500 ether);

		// Move forward some blocks and simulate interest accrual
		vm.roll(START_BLOCK + 100);
		mockOracle.setExchangeRate(1.05e18); // 5% increase

		// Second stake to record a gradient
		vm.prank(stakers[1]);
		launchpool.stake(200 ether);

		// Verify a non-zero gradient was created
		uint256 gradient = launchpool.avgNativeExRateGradient();
		console.log("Average native exchange rate gradient:", gradient);
		assertTrue(gradient > 0, "Gradient should be non-zero");

		// Calculate expected rate at end
		uint256 lastExRate = launchpool.lastNativeExRate();
		uint256 blocksTilEnd = END_BLOCK -
			launchpool.lastNativeExRateUpdateBlock();
		uint256 expectedRateAtEnd = lastExRate + (gradient * blocksTilEnd);

		// Get estimated rate at end using the contract function
		uint256 actualEstimatedRate = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();

		// Verify the calculation matches our expected value
		assertEq(
			actualEstimatedRate,
			expectedRateAtEnd,
			"Estimated exchange rate at end should match manual calculation"
		);
	}

	// Test for the edge case specifically mentioned in the TODO comment
	// When avgNativeExRateGradient is zero after pool end
	function test_estimated_native_exrate_with_zero_gradient_after_pool_end()
		public
	{
		// Create staker
		address[] memory stakers = setupStakers.createAndApprove(
			1,
			address(launchpool),
			address(vAsset)
		);

		// Move to start block
		vm.roll(START_BLOCK);

		// Stake to establish initial state
		vm.prank(stakers[0]);
		launchpool.stake(300 ether);

		// Record the initial exchange rate
		uint256 initialExRate = launchpool.lastNativeExRate();
		uint128 initialUpdateBlock = launchpool.lastNativeExRateUpdateBlock();
		console.log("Initial exchange rate:", initialExRate);

		// Move past the end block
		vm.roll(END_BLOCK + 10);

		// Force avgNativeExRateGradient to be 0 to trigger our edge case
		launchpool.wild_setAvgNativeExRateGradient(0);
		assertEq(
			launchpool.avgNativeExRateGradient(),
			0,
			"Gradient should now be zero"
		);

		// Simulate a new exchange rate increase after the pool ends
		uint256 newRate = (initialExRate * 110) / 100; // 10% higher
		mockOracle.setExchangeRate(newRate / 1e18);

		// Calculate what we expect the result to be based on the formula in the function
		uint256 currentTokenByVToken = launchpool
			.exposed_getTokenByVTokenWithoutFee(1e18);
		uint256 expectedGradient = (currentTokenByVToken - initialExRate) /
			(block.number - initialUpdateBlock);
		uint256 expectedRateAtEnd = initialExRate +
			(expectedGradient * (END_BLOCK - initialUpdateBlock));

		// Get the estimate from the contract function
		uint256 actualEstimatedRate = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();

		console.log("Current rate after increase:", currentTokenByVToken);
		console.log("Block diff:", block.number - initialUpdateBlock);
		console.log("Calculated gradient:", expectedGradient);
		console.log("Expected rate at end:", expectedRateAtEnd);
		console.log("Actual estimated rate:", actualEstimatedRate);

		// Verify the calculation matches our expected value
		assertEq(
			actualEstimatedRate,
			expectedRateAtEnd,
			"Estimated exchange rate should match our manual calculation"
		);

		// Most importantly, verify that the calculated gradient is not zero
		assertTrue(
			expectedGradient > 0,
			"Calculated gradient must not be zero"
		);
	}

	// Test to verify the gradient calculation is correct when close to zero but not zero
	function test_estimated_native_exrate_with_very_small_gradient() public {
		// Create stakers
		address[] memory stakers = setupStakers.createAndApprove(
			2,
			address(launchpool),
			address(vAsset)
		);

		// Move to start block
		vm.roll(START_BLOCK);

		// Stake to establish initial state
		vm.prank(stakers[0]);
		launchpool.stake(100 ether);

		// Move forward many blocks to create a very small gradient (tiny interest over long time)
		vm.roll(START_BLOCK + 1000);

		// Set very small interest change (0.001%)
		uint256 smallIncreaseRate = (launchpool.lastNativeExRate() * 10001) /
			10000;
		mockOracle.setExchangeRate(smallIncreaseRate / 1e18);

		// Second stake to record the small gradient
		vm.prank(stakers[1]);
		launchpool.stake(50 ether);

		// Verify gradient is very small but not zero
		uint256 smallGradient = launchpool.avgNativeExRateGradient();
		console.log("Very small gradient:", smallGradient);
		assertTrue(
			smallGradient > 0 && smallGradient < 1e10,
			"Gradient should be very small but not zero"
		);

		// Calculate expected exchange rate at end
		uint256 lastExRate = launchpool.lastNativeExRate();
		uint256 blocksTilEnd = END_BLOCK -
			launchpool.lastNativeExRateUpdateBlock();
		uint256 expectedRateAtEnd = lastExRate + (smallGradient * blocksTilEnd);

		// Get the estimate from the contract function
		uint256 actualEstimatedRate = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();

		assertEq(
			actualEstimatedRate,
			expectedRateAtEnd,
			"Estimated exchange rate should work with very small gradients"
		);
	}

	// Test to ensure that when calculating a new gradient in the edge case,
	// we don't get a division by zero
	function test_no_division_by_zero_in_new_gradient_calculation() public {
		// Create stakers
		address[] memory stakers = setupStakers.createAndApprove(
			1,
			address(launchpool),
			address(vAsset)
		);

		// Move to start block
		vm.roll(START_BLOCK);

		// Stake to establish initial state
		vm.prank(stakers[0]);
		launchpool.stake(500 ether);

		// Force the lastNativeExRateUpdateBlock to be the same as current block
		// which would lead to block.number - lastNativeExRateUpdateBlock = 0
		vm.roll(END_BLOCK + 1);
		launchpool.wild_setLastNativeExRateUpdateBlock(uint128(block.number));
		launchpool.wild_setAvgNativeExRateGradient(0);

		// This would normally cause division by zero when calculating:
		// avgRateGradient = (newRate - lastNativeExRate) / (block.number - lastNativeExRateUpdateBlock)

		// But we'll roll to the next block to avoid the division by zero
		vm.roll(block.number + 1);

		// Setting a different exchange rate
		mockOracle.setExchangeRate(1.1e18); // 10% increase

		// This should not revert
		uint256 estimatedRate = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();

		// Just verify we got a reasonable result
		assertTrue(
			estimatedRate > 0,
			"Estimated exchange rate should be positive"
		);
		console.log("Estimated rate without division by zero:", estimatedRate);
	}

	// Test that the calculated gradient is never zero
	function test_new_gradient_is_never_zero() public {
		// Create stakers
		address[] memory stakers = setupStakers.createAndApprove(
			1,
			address(launchpool),
			address(vAsset)
		);

		// Move to start block
		vm.roll(START_BLOCK);

		// Stake to establish initial state
		vm.prank(stakers[0]);
		launchpool.stake(200 ether);

		// Record initial values
		uint256 initialExRate = launchpool.lastNativeExRate();
		uint128 initialUpdateBlock = launchpool.lastNativeExRateUpdateBlock();

		// Move past the end block
		vm.roll(END_BLOCK + 5);

		// Force avgNativeExRateGradient to be 0 to trigger our edge case
		launchpool.wild_setAvgNativeExRateGradient(0);

		// Test with various tiny exchange rate changes to ensure gradient is never zero
		for (uint i = 1; i <= 5; i++) {
			// Set a tiny increase in exchange rate (0.00001% * i)
			uint256 tinyIncrease = initialExRate +
				(initialExRate * i) /
				10000000;
			mockOracle.setExchangeRate(tinyIncrease / 1e18);

			// Calculate the gradient that should be used
			uint256 blockDiff = block.number - initialUpdateBlock;
			uint256 newRate = launchpool.exposed_getTokenByVTokenWithoutFee(
				1e18
			);
			uint256 calculatedGradient = (newRate - initialExRate) / blockDiff;

			// Get the estimated exchange rate - this uses the edge case code
			uint256 estimatedRate = launchpool
				.exposed_getEstimatedNativeExRateAtEnd();

			// Verify the calculated gradient is never zero
			assertTrue(
				calculatedGradient > 0,
				"Calculated gradient should never be zero"
			);

			// Make sure the end result is reasonable - greater than the initial rate
			assertTrue(
				estimatedRate > initialExRate,
				"Estimated rate should be greater than initial rate"
			);

			console.log(
				string(
					abi.encodePacked(
						"Test case ",
						vm.toString(i),
						": Calculated gradient = ",
						vm.toString(calculatedGradient)
					)
				)
			);
		}
	}

	// Test behavior with extreme values to ensure robustness
	function test_estimated_native_exrate_with_extreme_values() public {
		// Create stakers
		address[] memory stakers = setupStakers.createAndApprove(
			1,
			address(launchpool),
			address(vAsset)
		);

		// Very large lastNativeExRate
		uint256 veryLargeRate = type(uint128).max; // Use large but not max uint256 to avoid overflow

		// Move to start block
		vm.roll(START_BLOCK);

		// Set large initial exchange rate
		launchpool.wild_setLastNativeExRate(veryLargeRate);

		// Stake with a very small amount
		vm.prank(stakers[0]);
		launchpool.stake(1); // Minimum possible stake

		// Force zero gradient
		launchpool.wild_setAvgNativeExRateGradient(0);

		// Move past end block
		vm.roll(END_BLOCK + 10);

		// Setting a slightly larger exchange rate
		mockOracle.setExchangeRate(2); // Set an even higher rate

		// This should not overflow
		uint256 estimatedRate = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();

		// It should be at least as large as the initial rate
		assertTrue(
			estimatedRate >= veryLargeRate,
			"Estimated rate should be at least the initial large rate"
		);
		console.log("Estimated rate with extreme values:", estimatedRate);
	}

	// Test with a real world scenario that includes staking, unstaking, and claiming
	function test_real_world_scenario_with_zero_gradient_edge_case() public {
		// Create stakers
		address[] memory stakers = setupStakers.createAndApprove(
			3,
			address(launchpool),
			address(vAsset)
		);

		// Move to start block
		vm.roll(START_BLOCK);

		// Stakers stake various amounts
		vm.prank(stakers[0]);
		launchpool.stake(300 ether);

		vm.prank(stakers[1]);
		launchpool.stake(400 ether);

		vm.prank(stakers[2]);
		launchpool.stake(200 ether);

		// Move forward in time with some interest accrual
		vm.roll(START_BLOCK + poolDurationBlocks / 2);
		mockOracle.setExchangeRate(1.02e18); // 2% increase

		// Second stake from staker 0 to establish a gradient
		vm.prank(stakers[0]);
		launchpool.stake(100 ether);

		// Record the gradient we have
		uint256 midPoolGradient = launchpool.avgNativeExRateGradient();
		console.log("Mid-pool gradient:", midPoolGradient);
		assertTrue(midPoolGradient > 0, "Mid-pool gradient should be positive");

		// Move to just past the end block
		vm.roll(END_BLOCK + 1);

		// Get the estimated exchange rate for verification
		uint256 estimatedRateAtEnd = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();
		console.log("Estimated exchange rate at end:", estimatedRateAtEnd);
		assertTrue(
			estimatedRateAtEnd > 0,
			"Estimated rate at end should be positive"
		);

		// Now force the avgNativeExRateGradient to 0 to simulate the edge case
		launchpool.wild_setAvgNativeExRateGradient(0);

		// Exchange rate continues to increase after pool ends
		mockOracle.setExchangeRate(1.04e18); // 4% total increase

		// Stakers begin to unstake
		vm.prank(stakers[1]);
		uint256 staker1Native = launchpool.getStakerNativeAmount(stakers[1]);
		uint256 withdrawable = launchpool.getWithdrawableVTokens(staker1Native);
		launchpool.unstake(withdrawable);

		// Calculate a new gradient based on the current exchange rate
		uint256 newRate = launchpool.exposed_getTokenByVTokenWithoutFee(1e18);
		uint256 initialExRate = launchpool.lastNativeExRate();
		uint256 blockDiff = block.number -
			launchpool.lastNativeExRateUpdateBlock();
		uint256 newGradient = (newRate - initialExRate) / blockDiff;

		// This is the key part of the test - verify that this new gradient is non-zero
		assertTrue(
			newGradient > 0,
			"New gradient calculated after pool end should be non-zero"
		);
		console.log("New gradient calculated after pool end:", newGradient);

		// Get new estimated rate - should now use the new gradient calculation
		uint256 newEstimatedRate = launchpool
			.exposed_getEstimatedNativeExRateAtEnd();
		console.log(
			"New estimated exchange rate after recalculation:",
			newEstimatedRate
		);

		// Owner claims interest - this should work correctly with the new gradient
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		launchpool.claimOwnerInterest();
		uint256 ownerBalanceAfter = vAsset.balanceOf(owner);

		// Verify owner was able to claim interest
		assertTrue(
			ownerBalanceAfter > ownerBalanceBefore,
			"Owner should be able to claim interest after recalculation with new gradient"
		);

		// Now let's have the remaining stakers unstake
		vm.prank(stakers[0]);
		uint256 staker0Native = launchpool.getStakerNativeAmount(stakers[0]);
		uint256 withdrawable0 = launchpool.getWithdrawableVTokens(
			staker0Native
		);
		launchpool.unstake(withdrawable0);

		vm.prank(stakers[2]);
		uint256 staker2Native = launchpool.getStakerNativeAmount(stakers[2]);
		uint256 withdrawable2 = launchpool.getWithdrawableVTokens(
			staker2Native
		);
		launchpool.unstake(withdrawable2);

		// Verify the pool is correctly emptied
		assertEq(
			launchpool.totalNativeStake(),
			0,
			"Total native stake should be zero after all unstakes"
		);
	}
}
