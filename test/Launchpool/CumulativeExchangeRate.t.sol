// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "../mocks/MockLaunchpool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

// @todo: Improve testcase later on when implementation for valid vAsset
contract CumulativeExchangeRateTest is Test {
	MockLaunchpool public launchpool;
	MockERC20 public projectToken;
	MockERC20 public vAsset;
	uint256 constant BLOCK_TIME = 6 seconds;

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
	}

	function testConstantEmissionRateWithOneStaker() public {
		// Arrange: deploy pool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

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
			(poolDurationBlocks / 2)) / stakeAmount;

		assertEq(
			actualExchangeRate,
			expectedExchangeRate,
			"Cumulative exchange rate different from expectation"
		);
	}

	function testConstantEmissionRateWithTwoStakersAtSameBlock() public {
		// Arrange: deploy pool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

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

		// 2. Someone stakes 500 vTokens at pool start
		address someoneElse = makeAddr("someone");
		uint256 stakeAmount2 = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(someoneElse, stakeAmount2);
		vm.startPrank(someoneElse); // acting as another investor
		vAsset.approve(address(launchpool), stakeAmount2);
		launchpool.stake(stakeAmount2);
		vm.stopPrank(); // return to original investor/signer

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
			(poolDurationBlocks / 2)) / (stakeAmount + stakeAmount2);
		assertEq(
			actualExchangeRate,
			expectedExchangeRate,
			"Cumulative exchange rate different from expectation"
		);
	}

	function testConstantEmissionRateWithTwoStakersAtDifferentBlocks() public {
		// Arrange: deploy pool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

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
			(poolDurationBlocks / 2)) / (stakeAmount);
		assertEq(
			actualExchangeRate,
			expectedExchangeRate,
			"Cumulative exchange rate different from expectation"
		);
		vm.stopPrank(); // return to original investor/signer
	}

	function testVariableEmissionRateWithOneStaker() public {
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
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

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
		uint256 expectedPendingExchangeRate = (// First period: from startBlock to first change
			emissionRateChanges[0] *
				(changeBlocks[1] - changeBlocks[0]) +
				// Second period: from first change to halfway point
				emissionRateChanges[1] *
				(startBlock + (poolDurationBlocks / 2) - changeBlocks[1])) /
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
			(// First period: from startBlock to first change (1/3 of pool duration)
			emissionRateChanges[0] *
				(changeBlocks[1] - changeBlocks[0]) +
				// Second period: from first change to second change (2/3 of pool duration)
				emissionRateChanges[1] *
				(changeBlocks[2] - changeBlocks[1]) +
				// Third period: from second chagne to 6/7 of pool duration
				emissionRateChanges[2] *
				(startBlock + (poolDurationBlocks * 6) / 7 - changeBlocks[2])) /
			stakeAmount;
		assertEq(
			pendingExchangeRate,
			expectedPendingExchangeRate,
			"Cumulative exchange rate different from expectation at halfway through the pool"
		);
	}

	function testVariableEmissionRateWithTwoStakersAtDifferentBlocks() public {
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
			startBlock,
			endBlock,
			maxVTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

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

		// 2. At 3/7 of pool duration, someone stakes 999 vTokens
		vm.roll(startBlock + (poolDurationBlocks * 3) / 7);
		address someoneElse = makeAddr("someone");
		uint256 stakeAmount2 = maxVTokensPerStaker - 1;
		vAsset.freeMintTo(someoneElse, stakeAmount2);
		vm.startPrank(someoneElse); // acting as another investor
		vAsset.approve(address(launchpool), stakeAmount2);
		launchpool.stake(stakeAmount2);
		vm.stopPrank();

		// Assert:
		// 1. Check cumulative exchange rate at the last block of the pool
		vm.roll(startBlock + poolDurationBlocks);
		uint256 pendingExchangeRate = launchpool.getPendingExchangeRate();
		uint256 actualCumulativeExchangeRate = launchpool
			.cumulativeExchangeRate() + pendingExchangeRate;
		// Calculate expected rate at pool end
		uint256 expectedCumulativeExchangeRate = (emissionRateChanges[0] * // First period: from startBlock to first change of emission rate
			(changeBlocks[1] - changeBlocks[0]) +
			// Second period: from first change to when someoneElse stakes
			emissionRateChanges[1] *
			(startBlock + (poolDurationBlocks * 3) / 7 - changeBlocks[1])) /
			(stakeAmount) +
			// Third period: from when someoneElse stakes to second change of emission rate
			(emissionRateChanges[1] *
				(changeBlocks[2] -
					(startBlock + (poolDurationBlocks * 3) / 7)) +
				// Fourth period: from second chagne to the end of the pool
				emissionRateChanges[2] *
				(startBlock + poolDurationBlocks - changeBlocks[2])) /
			(stakeAmount + stakeAmount2);
		assertEq(
			actualCumulativeExchangeRate,
			expectedCumulativeExchangeRate,
			"Cumulative exchange rate different from expectation at the end of the pool"
		);
	}

	// function testVariableEmissionRateWith4StakersAtDifferentBlocks() public {
	// 	// Arrange: deploy pool with same config as previous tests
	// 	uint128 poolDurationBlocks = uint128(14 days / BLOCK_TIME);
	// 	uint128 startBlock = uint128(block.number) + 100; // Start later to allow pre-start actions
	// 	uint128 endBlock = startBlock + poolDurationBlocks;
	// 	uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());

	// 	uint128[] memory changeBlocks = new uint128[](3);
	// 	changeBlocks[0] = startBlock;
	// 	changeBlocks[1] = startBlock + poolDurationBlocks / 3;
	// 	changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4;

	// 	uint256[] memory emissionRateChanges = new uint256[](3);
	// 	emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
	// 	emissionRateChanges[1] = 1e3 * (10 ** vAsset.decimals());
	// 	emissionRateChanges[2] = 9e2 * (10 ** vAsset.decimals());

	// 	launchpool = new MockLaunchpool(
	// 		address(this),
	// 		address(projectToken),
	// 		address(vAsset),
	// 		startBlock,
	// 		endBlock,
	// 		maxVTokensPerStaker,
	// 		changeBlocks,
	// 		emissionRateChanges
	// 	);

	// 	projectToken.transfer(
	// 		address(launchpool),
	// 		1e4 * (10 ** projectToken.decimals())
	// 	);

	// 	// Create test addresses
	// 	address alice = makeAddr("alice");
	// 	address bob = makeAddr("bob");
	// 	address charlie = makeAddr("charlie");
	// 	address dave = makeAddr("dave");

	// 	// Act:
	// 	// 1. First staker (alice) joins at block startBlock + 50 with 750 tokens
	// 	vm.roll(startBlock + 50);
	// 	uint256 aliceStake = 750 * (10 ** vAsset.decimals());
	// 	vAsset.freeMintTo(alice, aliceStake);
	// 	vm.prank(alice);
	// 	vAsset.approve(address(launchpool), aliceStake);
	// 	vm.prank(alice);
	// 	launchpool.stake(aliceStake);

	// 	// 2. Bob joins right before first emission rate change with 300 tokens
	// 	vm.roll(changeBlocks[1] - 1);
	// 	uint256 bobStake = 300 * (10 ** vAsset.decimals());
	// 	vAsset.freeMintTo(bob, bobStake);
	// 	vm.prank(bob);
	// 	vAsset.approve(address(launchpool), bobStake);
	// 	vm.prank(bob);
	// 	launchpool.stake(bobStake);

	// 	// 3. Charlie joins between rate changes with 523 tokens
	// 	vm.roll(startBlock + (poolDurationBlocks * 1) / 2);
	// 	uint256 charlieStake = 523 * (10 ** vAsset.decimals());
	// 	vAsset.freeMintTo(charlie, charlieStake);
	// 	vm.prank(charlie);
	// 	vAsset.approve(address(launchpool), charlieStake);
	// 	vm.prank(charlie);
	// 	launchpool.stake(charlieStake);

	// 	// 4. Dave joins after second rate change with remaining allowance
	// 	vm.roll(changeBlocks[2] + 100);
	// 	uint256 daveStake = maxVTokensPerStaker -
	// 		50 *
	// 		(10 ** vAsset.decimals());
	// 	vAsset.freeMintTo(dave, daveStake);
	// 	vm.prank(dave);
	// 	vAsset.approve(address(launchpool), daveStake);
	// 	vm.prank(dave);
	// 	launchpool.stake(daveStake);

	// 	// Calculate expected exchange rate segments
	// 	// First period: startBlock+50 to first change, Alice and Bob
	// 	uint256 period1Blocks = changeBlocks[1] - (startBlock + 50);
	// 	uint256 period1Rate = (emissionRateChanges[0] * period1Blocks) /
	// 		aliceStake;

	// 	// Second period: first change to halfway, Alice and Bob
	// 	uint256 halfwayBlock = startBlock + (poolDurationBlocks * 1) / 2;
	// 	uint256 period2Blocks = halfwayBlock - changeBlocks[1];
	// 	uint256 period2TotalStake = aliceStake + bobStake;
	// 	uint256 period2Rate = (emissionRateChanges[1] * period2Blocks) /
	// 		period2TotalStake;

	// 	// Third period: halfway to second change, Alice, Bob, and Charlie
	// 	uint256 period3Blocks = changeBlocks[2] - halfwayBlock;
	// 	uint256 period3TotalStake = aliceStake + bobStake + charlieStake;
	// 	uint256 period3Rate = (emissionRateChanges[1] * period3Blocks) /
	// 		period3TotalStake;

	// 	// Fourth period: second change to end, all stakers
	// 	uint256 period4Blocks = endBlock - changeBlocks[2];
	// 	uint256 period4TotalStake = aliceStake +
	// 		bobStake +
	// 		charlieStake +
	// 		daveStake;
	// 	uint256 period4Rate = (emissionRateChanges[2] * period4Blocks) /
	// 		period4TotalStake;

	// 	// Sum all periods
	// 	uint256 expectedRate = period1Rate +
	// 		period2Rate +
	// 		period3Rate +
	// 		period4Rate;

	// 	// Assert final rates
	// 	vm.roll(endBlock);
	// 	uint256 pendingRate = launchpool.getPendingExchangeRate();
	// 	uint256 finalRate = launchpool.cumulativeExchangeRate() + pendingRate;

	// 	assertEq(
	// 		finalRate,
	// 		expectedRate,
	// 		"Cumulative exchange rate at pool end different from expectation"
	// 	);
	// }
}
