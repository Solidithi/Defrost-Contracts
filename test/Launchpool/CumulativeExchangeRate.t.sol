// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

// @todo: Improve testcase later on when implementation for valid vAsset
contract CumulativeExchangeRateTest is Test {
	MockLaunchpool public launchpool;
	MockERC20 public projectToken;
	MockERC20 public vAsset;
	MockERC20 public nativeAsset;
	uint256 constant BLOCK_TIME = 6 seconds;

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
		nativeAsset = new MockERC20("Native Token", "NAT");
	}

	function test_constant_emission_rate_with_one_staker() public {
		// Arrange: deploy pool
		uint128[] memory changeBlocks = new uint128[](1);
		uint128 startBlock = uint128(block.number) + 1;
		changeBlocks[0] = startBlock;
		uint256[] memory emissionRateChanges = new uint256[](1);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		uint128 poolDurationBlocks = 70;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);
		uint256 scalingFactor = launchpool.SCALING_FACTOR();

		projectToken.transfer(
			address(launchpool),
			1e3 * (10 ** projectToken.decimals())
		);

		// Act:
		// 1. Stake 1000 vTokens at pool start (same as max amount per staker)
		uint256 stakeAmount = maxVTokensPerStaker;
		vAsset.approve(address(launchpool), stakeAmount);
		vm.roll(startBlock);
		launchpool.stake(stakeAmount);
		uint256 nativeStakeAmount = launchpool.totalStake();

		// Assert:
		// 1. Check cumulative exchange rate at pool start (should be 0)
		uint256 actualExchangeRate = launchpool.cumulativeExchangeRate();
		assertEq(
			actualExchangeRate,
			0,
			"Cumulative exchange rate is not 0 at pool start"
		);

		// 2. Call _getPendingExchangeRate() halfway through the pool (35 blocks)
		vm.roll(startBlock + poolDurationBlocks / 2);
		actualExchangeRate = launchpool.getPendingExchangeRate();
		uint256 expectedExchangeRate = (emissionRateChanges[0] *
			(poolDurationBlocks / 2) *
			scalingFactor) / nativeStakeAmount;

		assertEq(
			actualExchangeRate,
			expectedExchangeRate,
			"Cumulative exchange rate different from expectation"
		);
	}

	function test_constant_emission_rate_with_two_stakers_at_the_same_block()
		public
	{
		// Arrange: deploy pool
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);
		uint256 scalingFactor = launchpool.SCALING_FACTOR();

		projectToken.transfer(
			address(launchpool),
			1e3 * (10 ** projectToken.decimals())
		);

		// Act:
		// 1. I Stake 1000 vTokens at pool start (same as max amount per staker)
		uint256 stakeAmount = maxVTokensPerStaker;
		vAsset.approve(address(launchpool), stakeAmount);
		vm.roll(startBlock);
		launchpool.stake(stakeAmount);
		stakeAmount = launchpool.totalStake();

		// 2. Someone stakes 500 vTokens at pool start
		address someoneElse = makeAddr("someone");
		uint256 stakeAmount2 = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(someoneElse, stakeAmount2);
		vm.startPrank(someoneElse); // acting as another investor
		vAsset.approve(address(launchpool), stakeAmount2);
		launchpool.stake(stakeAmount2);
		vm.stopPrank(); // return to original investor/signer
		stakeAmount2 = launchpool.totalStake() - stakeAmount;

		// Assert:
		// 1. Check cumulative exchange rate at pool start (should be 0 bcuz tickBlockDelta is 0)
		uint256 actualExchangeRate = launchpool.cumulativeExchangeRate();
		assertEq(
			actualExchangeRate,
			0,
			"Cumulative exchange rate is not 0 at pool start"
		);

		// 2. Call _getPendingExchangeRate() halfway through the pool (35 blocks)
		vm.roll(startBlock + poolDurationBlocks / 2);
		actualExchangeRate = launchpool.getPendingExchangeRate();
		uint256 expectedExchangeRate = (emissionRateChanges[0] *
			(poolDurationBlocks / 2) *
			scalingFactor) / (stakeAmount + stakeAmount2);
		assertEq(
			actualExchangeRate,
			expectedExchangeRate,
			"Cumulative exchange rate different from expectation"
		);
	}

	function test_constant_emission_rate_with_two_stakers_at_different_blocks()
		public
	{
		// Arrange: deploy pool
		uint128[] memory changeBlocks = new uint128[](1);
		uint128 startBlock = uint128(block.number) + 1;
		changeBlocks[0] = startBlock;
		uint256[] memory emissionRateChanges = new uint256[](1);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		uint128 poolDurationBlocks = 70;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);
		uint256 scalingFactor = launchpool.SCALING_FACTOR();

		projectToken.transfer(
			address(launchpool),
			1e3 * (10 ** projectToken.decimals())
		);

		// Act:
		// 1. I Stake 1000 vTokens at pool start (same as max amount per staker)
		vm.roll(startBlock);
		uint256 stakeAmount = maxVTokensPerStaker;
		vAsset.approve(address(launchpool), stakeAmount);
		launchpool.stake(stakeAmount);
		stakeAmount = launchpool.totalStake();

		// 2. Someone stakes 500 vTokens at halfway throught the pool
		vm.roll(startBlock + poolDurationBlocks / 2);
		address someoneElse = makeAddr("someone");
		uint256 stakeAmount2 = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(someoneElse, stakeAmount2);
		vm.startPrank(someoneElse); // acting as another investor
		vAsset.approve(address(launchpool), stakeAmount2);
		launchpool.stake(stakeAmount2);

		// Assert:
		// 1. Call getCumulativeExchangeRate right after someoneElse stakes, at the same block, which is block 35
		// (there staking shouldn't has any effect on cumulativeExchangeRate yet)
		uint256 actualExchangeRate = launchpool.cumulativeExchangeRate();
		uint256 expectedExchangeRate = (emissionRateChanges[0] *
			(poolDurationBlocks / 2) *
			scalingFactor) / (stakeAmount);
		assertEq(
			actualExchangeRate,
			expectedExchangeRate,
			"Cumulative exchange rate different from expectation"
		);
		vm.stopPrank(); // return to original investor/signer
	}

	function test_variable_emission_rate_with_one_staker() public {
		// Arrange: deploy pool
		uint128 poolDurationBlocks = uint128(14 days / BLOCK_TIME);
		uint128 startBlock = uint128(block.number) + 1;
		uint128 endBlock = startBlock + poolDurationBlocks;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128[] memory changeBlocks = new uint128[](3);
		changeBlocks[0] = startBlock;
		changeBlocks[1] = startBlock + poolDurationBlocks / 3; // change at 1/3 of pool duration
		changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4; // chagne at 2/3 of pool duration
		uint256[] memory emissionRateChanges = new uint256[](3);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		emissionRateChanges[1] = 1e3 * (10 ** vAsset.decimals());
		emissionRateChanges[2] = 9e2 * (10 ** vAsset.decimals());

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);
		uint256 scalingFactor = launchpool.SCALING_FACTOR();

		projectToken.transfer(
			address(launchpool),
			1e3 * (10 ** projectToken.decimals())
		);

		// Act:
		// 1. I Stake 1000 vTokens at pool start (same as max amount per staker)
		vm.roll(startBlock);
		uint256 stakeAmount = maxVTokensPerStaker;
		vAsset.approve(address(launchpool), stakeAmount);
		launchpool.stake(stakeAmount);
		stakeAmount = launchpool.totalStake();

		// Assert:
		// 1. I Call get accumulated exchange rate right after staking
		uint256 actualExchangeRate = launchpool.cumulativeExchangeRate();
		assertEq(
			actualExchangeRate,
			0,
			"Cumulative exchange rate should be 0 at pool start"
		);

		// 2. Call _getPendingRewardRate rate at halfway through the pool
		vm.roll(startBlock + poolDurationBlocks / 2);
		uint256 pendingExchangeRate = launchpool.getPendingExchangeRate();
		// Calculate expected rate at halfway point
		uint256 expectedPendingExchangeRate = ((emissionRateChanges[0] *
			(changeBlocks[1] - changeBlocks[0]) +
			emissionRateChanges[1] *
			(startBlock + (poolDurationBlocks / 2) - changeBlocks[1])) *
			scalingFactor) / // First period: from startBlock to first change
			// Second period: from first change to halfway point
			stakeAmount;
		assertEq(
			pendingExchangeRate,
			expectedPendingExchangeRate,
			"Cumulative exchange rate different from expectation at halfway through the pool"
		);

		// 3. Call _getPendingRewardRate rate at 6/7 duration of the pool
		vm.roll(startBlock + (poolDurationBlocks * 6) / 7);
		pendingExchangeRate = launchpool.getPendingExchangeRate();
		// Calculate expected rate at halfway point
		expectedPendingExchangeRate =
			((emissionRateChanges[0] *
				(changeBlocks[1] - changeBlocks[0]) +
				emissionRateChanges[1] *
				(changeBlocks[2] - changeBlocks[1]) +
				emissionRateChanges[2] *
				(startBlock + (poolDurationBlocks * 6) / 7 - changeBlocks[2])) *
				scalingFactor) / // First period: from startBlock to first change (1/3 of pool duration)
			// Second period: from first change to second change (2/3 of pool duration)
			// Third period: from second chagne to 6/7 of pool duration
			stakeAmount;
		assertEq(
			pendingExchangeRate,
			expectedPendingExchangeRate,
			"Cumulative exchange rate different from expectation at halfway through the pool"
		);
	}

	function test_variable_emission_rate_with_two_stakers_at_different_blocks()
		public
	{
		// Arrange: deploy pool
		uint128 poolDurationBlocks = uint128(14 days / BLOCK_TIME);
		uint128 startBlock = uint128(block.number) + 1;
		uint128 endBlock = startBlock + poolDurationBlocks;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128[] memory changeBlocks = new uint128[](3);
		changeBlocks[0] = startBlock;
		changeBlocks[1] = startBlock + poolDurationBlocks / 3; // change at 1/3 of pool duration
		changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4; // change at 2/3 of pool duration
		uint256[] memory emissionRateChanges = new uint256[](3);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		emissionRateChanges[1] = 1e3 * (10 ** vAsset.decimals());
		emissionRateChanges[2] = 9e2 * (10 ** vAsset.decimals());

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);
		uint256 scalingFactor = launchpool.SCALING_FACTOR();

		projectToken.transfer(
			address(launchpool),
			1e3 * (10 ** projectToken.decimals())
		);

		// Act:
		// 1. I Stake 1000 vTokens at pool start (same as max amount per staker)
		vm.roll(startBlock);
		uint256 stakeAmount = maxVTokensPerStaker;
		vAsset.approve(address(launchpool), stakeAmount);
		launchpool.stake(stakeAmount);
		stakeAmount = launchpool.totalStake();

		// 2. At 3/7 of pool duration, someone stakes 999 vTokens
		vm.roll(startBlock + (poolDurationBlocks * 3) / 7);
		address someoneElse = makeAddr("someone");
		uint256 stakeAmount2 = maxVTokensPerStaker - 1;
		vAsset.freeMintTo(someoneElse, stakeAmount2);
		vm.startPrank(someoneElse); // acting as another investor
		vAsset.approve(address(launchpool), stakeAmount2);
		launchpool.stake(stakeAmount2);
		vm.stopPrank();

		stakeAmount2 = launchpool.totalStake() - stakeAmount;

		// Assert:
		// 1. Check cumulative exchange rate at the last block of the pool
		vm.roll(startBlock + poolDurationBlocks);
		uint256 pendingExchangeRate = launchpool.getPendingExchangeRate();
		uint256 actualCumulativeExchangeRate = launchpool
			.cumulativeExchangeRate() + pendingExchangeRate;
		// Calculate expected rate at pool end
		uint256 expectedCumulativeExchangeRate = ((emissionRateChanges[0] *
			(changeBlocks[1] - changeBlocks[0]) +
			emissionRateChanges[1] *
			(startBlock + (poolDurationBlocks * 3) / 7 - changeBlocks[1])) *
			scalingFactor) / // First period: from startBlock to first change of emission rate
			// Second period: from first change to when someoneElse stakes
			(stakeAmount) +
			// Third period: from when someoneElse stakes to second change of emission rate
			((emissionRateChanges[1] *
				(changeBlocks[2] -
					(startBlock + (poolDurationBlocks * 3) / 7)) +
				emissionRateChanges[2] *
				(startBlock + poolDurationBlocks - changeBlocks[2])) *
				scalingFactor) /
			// Fourth period: from second chagne to the end of the pool
			(stakeAmount + stakeAmount2);
		assertEq(
			actualCumulativeExchangeRate,
			expectedCumulativeExchangeRate,
			"Cumulative exchange rate different from expectation at the end of the pool"
		);
	}

	function test_variable_emission_rate_with_4_stakers_at_different_blocks()
		public
	{
		// Arrange: deploy pool with same config as previous tests
		uint128 poolDurationBlocks = uint128(14 days / BLOCK_TIME);
		uint128 startBlock = uint128(block.number) + 1; // Start later to allow pre-start actions
		uint128 endBlock = startBlock + poolDurationBlocks;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());

		uint128[] memory changeBlocks = new uint128[](3);
		changeBlocks[0] = startBlock;
		changeBlocks[1] = startBlock + poolDurationBlocks / 3;
		changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4;

		uint256[] memory emissionRateChanges = new uint256[](3);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		emissionRateChanges[1] = 1e3 * (10 ** vAsset.decimals());
		emissionRateChanges[2] = 9e2 * (10 ** vAsset.decimals());

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);
		uint256 scalingFactor = launchpool.SCALING_FACTOR();

		projectToken.transfer(
			address(launchpool),
			1e6 * (10 ** projectToken.decimals())
		);

		// Create test addresses
		address alice = makeAddr("alice");
		address bob = makeAddr("bob");
		address charlie = makeAddr("charlie");
		address dave = makeAddr("dave");

		// Act:
		// 1. First staker (alice) joins at block startBlock + 50 with 750 tokens
		vm.roll(startBlock);
		uint256 aliceStake = 750 * (10 ** vAsset.decimals());
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		console.log(
			"Adjusted cumulative exchange after staking: %d",
			launchpool.cumulativeExchangeRate()
		);
		vm.stopPrank();
		aliceStake = launchpool.totalStake();

		// 2. Bob joins right before first emission rate change with 300 tokens
		vm.roll(changeBlocks[1] - 1);
		uint256 bobStake = 300 * (10 ** vAsset.decimals());
		vAsset.freeMintTo(bob, bobStake);
		vm.startPrank(bob);
		vAsset.approve(address(launchpool), bobStake);
		launchpool.stake(bobStake);
		console.log(
			"Adjusted cumulative exchange after staking: %d",
			launchpool.cumulativeExchangeRate()
		);
		vm.stopPrank();
		bobStake = launchpool.totalStake() - aliceStake;

		// 3. Charlie joins at halfway through the pool with 523 tokens
		vm.roll(startBlock + (poolDurationBlocks * 1) / 2);
		uint256 charlieStake = 523 * (10 ** vAsset.decimals());
		vAsset.freeMintTo(charlie, charlieStake);
		vm.prank(charlie);
		vAsset.approve(address(launchpool), charlieStake);
		vm.prank(charlie);
		launchpool.stake(charlieStake);
		charlieStake = launchpool.totalStake() - aliceStake - bobStake;

		// 4. Dave joins after second rate change with remaining allowance
		vm.roll(changeBlocks[2] + 100);
		uint256 daveStake = maxVTokensPerStaker -
			50 *
			(10 ** vAsset.decimals());
		vAsset.freeMintTo(dave, daveStake);
		vm.prank(dave);
		vAsset.approve(address(launchpool), daveStake);
		vm.prank(dave);
		launchpool.stake(daveStake);
		daveStake =
			launchpool.totalStake() -
			aliceStake -
			bobStake -
			charlieStake;

		// Calculate expected exchange rate segments
		// First period: startBlock+50 to first change, Alice and Bob involved
		uint256 period1Rate = ((emissionRateChanges[0] *
			(changeBlocks[1] - 1 - startBlock) *
			scalingFactor) / aliceStake) +
			(((emissionRateChanges[0] * 1) * scalingFactor) /
				(aliceStake + bobStake));

		// Second period: first change to halfway, Alice and Bob involved
		uint256 halfwayBlock = startBlock + poolDurationBlocks / 2;
		uint256 period2Blocks = halfwayBlock - changeBlocks[1];
		uint256 period2TotalStake = aliceStake + bobStake;
		uint256 period2Rate = ((emissionRateChanges[1] * period2Blocks) *
			scalingFactor) / period2TotalStake;

		// Third period: halfway to second change, Alice, Bob, and Charlie
		uint256 period3Blocks = changeBlocks[2] - halfwayBlock;
		uint256 period3TotalStake = aliceStake + bobStake + charlieStake;
		uint256 period3Rate = ((emissionRateChanges[1] * period3Blocks) *
			scalingFactor) / period3TotalStake;

		// Fourth period: second change to when Dave stakes. Alice, Bob and Charlie involved
		uint256 period4Blocks = 100;
		uint256 period4TotalStake = aliceStake + bobStake + charlieStake;
		uint256 period4Rate = ((emissionRateChanges[2] * period4Blocks) *
			scalingFactor) / period4TotalStake;

		// Fifth period: After Dave stakes to the end of pool . Alice, Bob, Charlie, and Dave involved
		uint256 period5Block = endBlock - (changeBlocks[2] + 100);
		uint256 period5TotalStake = aliceStake +
			bobStake +
			charlieStake +
			daveStake;
		uint256 period5Stake = ((emissionRateChanges[2] * period5Block) *
			scalingFactor) / period5TotalStake;

		// Sum all periods
		uint256 expectedRate = period1Rate +
			period2Rate +
			period3Rate +
			period4Rate +
			period5Stake;

		// Assert final rates
		vm.roll(endBlock);
		uint256 pendingRate = launchpool.getPendingExchangeRate();
		uint256 finalRate = launchpool.cumulativeExchangeRate() + pendingRate;

		assertEq(
			finalRate,
			expectedRate,
			"Cumulative exchange rate at pool end different from expectation"
		);
	}
}
