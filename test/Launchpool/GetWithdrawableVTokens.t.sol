// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { console } from "forge-std/console.sol";
import { DeployMockXCMOracle } from "test/testutils/DeployMockXCMOracle.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";
import { SetupStakers } from "test/testutils/SetupStakers.sol";

contract GetWithdrawableVTokensTest is Test {
	MockLaunchpool launchpool;
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	DeployMockXCMOracle mockOracleDeployer = new DeployMockXCMOracle();
	MockXCMOracle mockOracle;
	SetupStakers setupStakers = new SetupStakers();

	address owner;
	address platformAdmin;
	address[] stakers;

	// Constants for testing
	uint128 public START_BLOCK;
	uint128 public END_BLOCK;
	uint256 public constant MAX_VSTAKER = 1000 ether;
	uint256 public constant BLOCK_TIME = 6 seconds;
	uint128 public poolDurationBlocks = uint128(14 days) / uint128(BLOCK_TIME);

	// Initial exchange rate and stakes
	uint256 public constant INITIAL_EXCHANGE_RATE = 1.2e18; // 1.2 native tokens per vToken
	uint256 public constant INITIAL_STAKE_AMOUNT = 500 ether;

	function setUp() public {
		owner = address(this);
		platformAdmin = makeAddr("platformAdmin");

		// Deploy mock tokens
		projectToken = new MockERC20("Project Token", "PT");
		vAsset = new MockERC20("vAsset Token", "vToken");
		nativeAsset = new MockERC20("Native Asset", "Native");

		// Deploy mock xcm oracle with 1.2 initial rate, 10 block interval, 8% APY, 6 seconds block time
		mockOracle = MockXCMOracle(
			mockOracleDeployer.deploy(INITIAL_EXCHANGE_RATE, 10, 80000, 6)
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
		launchpool.wild_setOwnerShareOfInterest(90); // 90% for owner, 10% as platform fee

		// Setup stakers
		stakers = setupStakers.createAndApprove(
			3,
			address(launchpool),
			address(vAsset)
		);
	}

	// Helper function to simulate staking with multiple users
	function _setupStakingScenario() internal {
		vm.roll(START_BLOCK);

		// Stake with multiple users
		for (uint i = 0; i < stakers.length; i++) {
			vm.prank(stakers[i]);
			launchpool.stake(INITIAL_STAKE_AMOUNT);
		}
	}

	// Test getWithdrawableVTokens during active pool time
	function test_get_withdrawable_v_tokens_during_pool_time() public {
		_setupStakingScenario();

		// Stake amount should convert back exactly to the same vTokens during pool time
		uint256 nativeAmount = 300 ether; // Native token amount
		uint256 expectedVTokens = (nativeAmount / INITIAL_EXCHANGE_RATE) * 1e18; // 300 / 1.2 = 250 vTokens

		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		assertApproxEqRel(
			withdrawableVTokens,
			expectedVTokens,
			0.0001e18, // 0.01% tolerance
			"During pool time, native amount should convert correctly to vTokens"
		);
	}

	// Test getWithdrawableVTokens after pool end with gradient=0 and updated exchange rate
	function test_get_withdrawable_v_tokens_after_pool_end_with_zero_gradient()
		public
	{
		_setupStakingScenario();

		// Jump to pool end
		vm.roll(END_BLOCK + 1);

		// First withdrawal should establish a gradient
		uint256 nativeAmount = 300 ether;
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		// At this point, avgNativeExRateGradient is likely 0 as no updates happened yet
		// The function should update the rate internally and calculate correctly

		// Validate result still match expected conversion
		uint256 expectedVTokens = (nativeAmount / INITIAL_EXCHANGE_RATE) * 1e18;
		assertApproxEqRel(
			withdrawableVTokens,
			expectedVTokens,
			0.001e18,
			"After pool end with zero gradient, should convert correctly"
		);
	}

	// Test with increased exchange rate at end of pool
	function test_get_withdrawable_v_tokens_with_changed_rate_at_pool_end()
		public
	{
		_setupStakingScenario();

		// First update exchange rate normally during pool
		vm.roll(START_BLOCK + 100);
		vm.prank(stakers[0]);
		launchpool.stake(100 ether);

		// Simulate an increase in exchange rate over time
		vm.roll(END_BLOCK);
		uint256 increasedRate = (INITIAL_EXCHANGE_RATE * 110) / 100; // 10% increase
		mockOracle.setExchangeRate(increasedRate);

		// Make a stake to update the rate gradient
		vm.prank(stakers[1]);
		launchpool.stake(50 ether);

		// Now check withdrawable amount after pool end
		vm.roll(END_BLOCK + 1);
		uint256 nativeAmount = 300 ether;
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		// Expected vTokens should be calculated using the estimated rate at pool end
		// This should be close to the increased rate
		uint256 expectedVTokens = (nativeAmount * 1e18) / increasedRate;

		assertApproxEqRel(
			withdrawableVTokens,
			expectedVTokens,
			0.01e18, // 1% tolerance due to estimation
			"After rate increase, should calculate withdrawable vTokens based on end rate"
		);
	}

	// Test edge case: zero native amount
	function test_get_withdrawable_v_tokens_zero_native_amount() public {
		_setupStakingScenario();

		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(0);
		assertEq(
			withdrawableVTokens,
			0,
			"Zero native amount should return zero withdrawable vTokens"
		);
	}

	// Test edge case: very large native amount
	function test_get_withdrawable_v_tokens_large_native_amount() public {
		_setupStakingScenario();

		// Add substantial vAssets to the pool
		vAsset.freeMintTo(address(launchpool), 10000 ether);

		// Try to withdraw a very large amount larger than all native values in pool
		uint256 largeNativeAmount = ((vAsset.balanceOf(address(launchpool)) *
			INITIAL_EXCHANGE_RATE *
			110) / 100) / 1e18;
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			largeNativeAmount
		);

		// Should be capped by total vAsset in pool
		uint256 totalVAssetStaked = launchpool.getTotalStakedVTokens();
		assertEq(
			withdrawableVTokens,
			totalVAssetStaked,
			"Very large native amount should be capped by total vAsset staked"
		);
	}

	// Test case where calculation would exceed available vAssets
	function test_get_withdrawable_v_tokens_exceed_available_v_assets() public {
		_setupStakingScenario();

		// Simulate some withdrawal, reducing vAsset balance but not updating totalNativeStake
		uint256 vTokensToRemove = 700 ether;
		vm.prank(address(launchpool));
		address fooAddr = makeAddr("foo"); // Foo address for burning tokens
		vAsset.transfer(fooAddr, vTokensToRemove); // Send tokens to burn address instead

		// Try to withdraw all native stake (which would normally require more vAssets than available)
		uint256 totalNative = launchpool.totalNativeStake();
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			totalNative
		);

		// Withdrawable amount should be capped by available vAssets
		uint256 remainingVAssets = vAsset.balanceOf(address(launchpool));
		assertEq(
			withdrawableVTokens,
			remainingVAssets,
			"Withdrawable amount should be limited by available vAssets"
		);
	}

	// Test with a changing exchange rate over time
	function test_get_withdrawable_v_tokens_with_increasing_exchange_rate()
		public
	{
		_setupStakingScenario();

		// Simulate multiple exchange rate changes during the pool lifetime
		uint256 steps = 10;
		uint256[] memory increments = new uint256[](steps);
		increments[0] = 5; // 5% increase
		increments[1] = 3; // 3% increase
		increments[2] = 7; // 7% increase
		increments[3] = 2; // 2% increase
		increments[4] = 4; // 4% increase
		increments[5] = 5; // 5% increase
		increments[6] = 3; // 3% increase
		increments[7] = 7; // 7% increase
		increments[8] = 2; // 2% increase
		increments[9] = 4; // 4% increase
		// Initial rate is 1.2, so at endBlock, it should be around 1.704 at pool end

		uint256 currentRate = INITIAL_EXCHANGE_RATE;
		uint256 blockStep = poolDurationBlocks / steps;

		// Update exchange rate at intervals
		for (uint i = 0; i < increments.length; i++) {
			vm.roll(START_BLOCK + (blockStep * (i + 1)));
			currentRate = (currentRate * (100 + increments[i])) / 100;
			mockOracle.setExchangeRate(currentRate);

			// Make stakes to update the gradient
			vm.prank(stakers[i % stakers.length]);
			launchpool.stake(50 ether);
		}

		// Check after pool end
		vm.roll(END_BLOCK + 1);
		uint256 nativeAmount = 300 ether;
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		// Expected exchange rate at end should factor in all increases
		// This test verifies the gradient is calculated correctly from multiple data points
		uint256 expectedVTokens = (nativeAmount * 1e18) / currentRate;

		assertApproxEqRel(
			withdrawableVTokens,
			expectedVTokens,
			0.00001e18, // 0.001% tolerance for estimation differences
			"Should calculate correct withdrawal amount after multiple rate changes"
		);
	}

	// Test that the maxima of totalVAssetStaked works as expected
	function test_get_withdrawable_v_tokens_max_total_v_asset_staked() public {
		_setupStakingScenario();

		// Intentionally lower the exchange rate to make withdrawal calculations exceed vAsset balance
		mockOracle.setExchangeRate(INITIAL_EXCHANGE_RATE / 2);

		// Get total native stake and calculate how many vTokens it would require at the new lower rate
		uint256 totalNative = launchpool.totalNativeStake();
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			totalNative
		);

		// Should be capped by total vAsset in pool
		uint256 totalVAssetStaked = launchpool.getTotalStakedVTokens();
		assertEq(
			withdrawableVTokens,
			totalVAssetStaked,
			"Should be capped by total vAsset staked when exchange rate drops"
		);
	}

	// Test calculation at the exact pool end block
	function test_get_withdrawable_v_tokens_at_pool_end_block() public {
		_setupStakingScenario();

		// Move to exactly pool end block
		vm.roll(END_BLOCK);

		// Increase exchange rate
		uint256 newRate = (INITIAL_EXCHANGE_RATE * 110) / 100;
		mockOracle.setExchangeRate(newRate);

		uint256 nativeAmount = 300 ether;
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		// During pool time (including exactly at end block), should use simple conversion
		uint256 expectedVTokens = (nativeAmount * 1e18) / newRate;

		assertApproxEqRel(
			withdrawableVTokens,
			expectedVTokens,
			0.001e18,
			"At exact pool end, should use current exchange rate"
		);
	}

	// Test correct behavior with multiple unstakes after pool end
	function test_get_withdrawable_v_tokens_multiple_unstakes_after_pool_end()
		public
	{
		_setupStakingScenario();

		// Simulate increased exchange rate at end
		vm.roll(END_BLOCK);
		uint256 endRate = (INITIAL_EXCHANGE_RATE * 120) / 100; // 20% increase
		mockOracle.setExchangeRate(endRate);

		// Move after pool end
		vm.roll(END_BLOCK + 1);

		// First unstake to establish gradient
		vm.startPrank(stakers[0]);
		uint256 stakerNativeAmount = launchpool.getStakerNativeAmount(
			stakers[0]
		);
		uint256 withdrawableVTokens1 = launchpool.getWithdrawableVTokens(
			stakerNativeAmount
		);
		launchpool.unstake(withdrawableVTokens1);
		vm.stopPrank();

		// Check withdrawable amount for second staker
		vm.startPrank(stakers[1]);
		uint256 stakerNativeAmount2 = launchpool.getStakerNativeAmount(
			stakers[1]
		);
		uint256 withdrawableVTokens2 = launchpool.getWithdrawableVTokens(
			stakerNativeAmount2
		);

		// Should be consistent with first calculation (proportional to native amount)
		uint256 expectedVTokens = (stakerNativeAmount2 * withdrawableVTokens1) /
			stakerNativeAmount;

		assertApproxEqRel(
			withdrawableVTokens2,
			expectedVTokens,
			0.01e18,
			"Second unstake should get consistent withdrawable amount after first unstake"
		);
		vm.stopPrank();
	}

	// Test with updateNativeTokenExchangeRate forcing gradient update after pool end
	function test_get_withdrawable_v_tokens_forced_gradient_update_after_pool_end()
		public
	{
		_setupStakingScenario();

		// Assert that gradient is still 0
		assertEq(
			launchpool.avgNativeExRateGradient(),
			0,
			"Gradient should still be 0 after 3 stakers staked at the same startBlock"
		);

		// Move to after pool end without any rate updates during pool
		vm.roll(END_BLOCK + 1);

		// Force an update of the exchange rate gradient via unstake
		uint256 newExchangeRate = 1.5e18;
		mockOracle.setExchangeRate(newExchangeRate);
		vm.prank(stakers[0]);
		uint256 smallAmount = 10 ether;
		launchpool.unstake(smallAmount);

		// Now check withdrawable amount for another user
		uint256 nativeAmount = 300 ether;
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		// Should be based on the updated gradient now
		uint256 exRateGradient = launchpool.avgNativeExRateGradient();
		uint256 expectedExRate = launchpool.lastNativeExRate() +
			(exRateGradient *
				(launchpool.endBlock() -
					launchpool.lastNativeExRateUpdateBlock()));

		// Fix: Use the correct formula for expected vTokens
		uint256 expectedVTokens = (nativeAmount * launchpool.ONE_VTOKEN()) /
			expectedExRate;
		assertApproxEqRel(
			withdrawableVTokens,
			expectedVTokens,
			0.01e18,
			"After forced gradient update, should calculate based on updated rate"
		);
	}

	// Test fuzz with random native amounts
	function test_fuzz_get_withdrawable_v_tokens(uint256 nativeAmount) public {
		// Bound to reasonable values to avoid overflow
		nativeAmount = bound(nativeAmount, 0, 1000000 ether);

		_setupStakingScenario();

		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			nativeAmount
		);

		if (nativeAmount == 0) {
			// Zero input should return zero
			assertEq(
				withdrawableVTokens,
				0,
				"Zero native amount should return zero vTokens"
			);
		} else {
			// Non-zero input should return proportional amount
			uint256 expectedVTokens = (nativeAmount * 1e18) /
				INITIAL_EXCHANGE_RATE;
			uint256 totalVAssetStaked = launchpool.getTotalStakedVTokens();

			// Result should be the min of calculated value and total staked
			uint256 expectedResult = expectedVTokens;
			if (expectedVTokens > totalVAssetStaked) {
				expectedResult = totalVAssetStaked;
			}

			assertApproxEqRel(
				withdrawableVTokens,
				expectedResult,
				0.0001e18,
				"Should calculate correct withdrawable amount for any valid input"
			);
		}
	}
}
