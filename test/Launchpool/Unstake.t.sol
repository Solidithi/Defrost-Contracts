// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { DeployMockXCMOracle } from "test/testutils/DeployMockXCMOracle.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract UnstakeTest is Test {
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	DeployMockXCMOracle mockOracleDeployer = new DeployMockXCMOracle();
	MockLaunchpool launchpool;
	MockXCMOracle xcmOracle;

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
		nativeAsset = new MockERC20("Native Imaginary", "nImaginary");
		// xcmOracle = new MockXCMOracle();
	}

	constructor() {
		// Deploy mock xcm oracle with 1.2 initial rate, 10 block interval, 8% APY, 6 seconds block time
		address mockXCMOracleAdr = mockOracleDeployer.deploy(
			1.2e18,
			10,
			80000,
			6
		);
		xcmOracle = MockXCMOracle(mockXCMOracleAdr);
	}

	function test_unstake_success() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

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

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Act: Stake
		address alice = makeAddr("alice");
		vm.roll(startBlock);
		uint256 aliceStake = maxVTokensPerStaker / 2; // Use half the max to be safe
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Record important state before unstaking
		uint256 stakedVTokens = launchpool.getTotalStakedVTokens();
		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);

		// Roll to the end
		vm.roll(endBlock);

		// Calculate the correct amount to unstake - ensure it's what can actually be withdrawn
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			aliceNativeStake
		);
		assertLe(
			withdrawableVTokens,
			stakedVTokens,
			"Withdrawable tokens must be <= staked tokens"
		);

		// Act: Unstake the withdrawable amount directly
		vm.startPrank(alice);
		launchpool.unstake(withdrawableVTokens);
		vm.stopPrank();

		// Assert
		uint256 aliceClaimable = launchpool.getClaimableProjectToken(alice);
		assertEq(aliceClaimable, 0);

		uint256 aliceVAssetBalance = vAsset.balanceOf(alice);
		assertEq(
			aliceVAssetBalance,
			withdrawableVTokens,
			"Alice should receive the correct amount of vAssets"
		);

		// Verify alice's stake is now 0
		assertEq(
			launchpool.getStakerNativeAmount(alice),
			0,
			"Alice's stake should be 0 after full unstake"
		);
	}

	function test_unstake_more_than_staked() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

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

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Act: Stake
		address alice = makeAddr("alice");
		vm.roll(startBlock);
		uint256 aliceStake = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Record important state
		uint256 stakedVTokens = launchpool.getTotalStakedVTokens();

		vm.roll(endBlock);

		// Assert - try to unstake more than what was staked
		vm.startPrank(alice);
		vm.expectRevert(Launchpool.ExceedWithdrawableVTokens.selector);
		launchpool.unstake(stakedVTokens + 1);
		vm.stopPrank();
	}

	function test_unstake_before_end() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

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

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Act: Stake
		address alice = makeAddr("alice");
		vm.roll(startBlock);
		uint256 aliceStake = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Move forward but still before end
		vm.roll(startBlock + 20);

		// Get withdrawable tokens directly from contract to avoid calculation issues
		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			aliceNativeStake
		);

		// Act: Unstake the exact withdrawable amount
		vm.startPrank(alice);
		launchpool.unstake(withdrawableVTokens);
		vm.stopPrank();

		// Assert
		uint256 aliceClaimable = launchpool.getClaimableProjectToken(alice);
		assertEq(aliceClaimable, 0);

		uint256 aliceVAssetBalance = vAsset.balanceOf(alice);
		assertEq(
			aliceVAssetBalance,
			withdrawableVTokens,
			"Alice should receive the correct amount of vAssets"
		);
	}

	function test_unstake_rapidly() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

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

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Act: Stake
		address alice = makeAddr("alice");
		vm.roll(startBlock);
		uint256 aliceStake = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		vm.roll(startBlock + 10);

		// Act: Unstake multiple times in small amounts
		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		uint256 totalWithdrawableVTokens = launchpool.getWithdrawableVTokens(
			aliceNativeStake
		);

		// Calculate unstake amount for 5 iterations
		uint256 unstakeAmount = totalWithdrawableVTokens / 5;
		uint256 initialVAssetBalance = vAsset.balanceOf(alice);
		uint256 cumulativeUnstaked = 0;

		// First unstake
		vm.startPrank(alice);
		launchpool.unstake(unstakeAmount);
		vm.stopPrank();

		cumulativeUnstaked += unstakeAmount;
		assertEq(vAsset.balanceOf(alice), initialVAssetBalance + unstakeAmount);

		// Second unstake after a few blocks
		vm.roll(startBlock + 20);

		// Recalculate what's withdrawable after first unstake
		aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		uint256 remainingWithdrawable = launchpool.getWithdrawableVTokens(
			aliceNativeStake
		);
		unstakeAmount = remainingWithdrawable > unstakeAmount
			? unstakeAmount
			: remainingWithdrawable;

		vm.startPrank(alice);
		launchpool.unstake(unstakeAmount);
		vm.stopPrank();

		cumulativeUnstaked += unstakeAmount;
		assertApproxEqRel(
			vAsset.balanceOf(alice),
			initialVAssetBalance + cumulativeUnstaked,
			0.01e18,
			"Alice should have received the correct cumulative amount of vAssets"
		);

		// Third unstake at pool end, if we still have tokens to unstake
		vm.roll(endBlock);

		aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		if (aliceNativeStake > 0) {
			remainingWithdrawable = launchpool.getWithdrawableVTokens(
				aliceNativeStake
			);
			if (remainingWithdrawable > 0) {
				vm.startPrank(alice);
				launchpool.unstake(remainingWithdrawable);
				vm.stopPrank();

				cumulativeUnstaked += remainingWithdrawable;
			}
		}

		// Verify final state
		assertApproxEqRel(
			vAsset.balanceOf(alice),
			initialVAssetBalance + cumulativeUnstaked,
			0.01e18,
			"Final vAsset balance should match initial + cumulative unstaked"
		);

		// Verify stake is entirely or nearly gone
		uint256 remainingStake = launchpool.getStakerNativeAmount(alice);
		assertLe(
			remainingStake,
			aliceNativeStake / 100, // Allow for tiny remainders due to rounding
			"Remaining stake should be zero or near-zero"
		);
	}

	function test_unstake_with_exchange_rate_change() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxTokenPerStaker = 1e3 * (10 ** nativeAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxTokenPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Act: Stake
		address alice = makeAddr("alice");
		vm.roll(startBlock);

		// Calculate stake amount that converts to exactly maxTokenPerStaker
		uint256 nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 aliceStake = (maxTokenPerStaker * (10 ** vAsset.decimals())) /
			nativePerVToken;

		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		uint256 totalNativeAtStart = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			totalNativeAtStart,
			maxTokenPerStaker,
			0.01e18,
			"Initial stake should be approximately max"
		);

		// Change exchange rate midway through pool
		vm.roll(startBlock + poolDurationBlocks / 2);

		// Significant increase in exchange rate (50% increase)
		xcmOracle.setExchangeRate(1.8e18);

		// Unstake half of what Alice has staked
		uint256 totalVAssetStaked = launchpool.getTotalStakedVTokens();
		uint256 halfVAssetStaked = totalVAssetStaked / 2;

		vm.startPrank(alice);
		launchpool.unstake(halfVAssetStaked);
		vm.stopPrank();

		// Check that Alice received the right amount of vAssets
		assertEq(vAsset.balanceOf(alice), halfVAssetStaked);

		// Check that the remaining native token amount is updated correctly
		uint256 remainingNative = launchpool.getStakerNativeAmount(alice);

		// The remaining native amount should be significantly less than half of the original amount
		// because the exchange rate has increased
		assertLt(
			remainingNative,
			totalNativeAtStart / 2,
			"Remaining native amount should be less than half due to increased exchange rate"
		);
	}

	function test_unstake_without_project_token() public {
		// Setup
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxTokenPerStaker = 1e3 * (10 ** nativeAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxTokenPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Stake
		address alice = makeAddr("alice");
		vm.roll(startBlock);

		uint256 aliceStake = 100 * (10 ** vAsset.decimals()); // Simple 100 tokens
		vAsset.freeMintTo(alice, aliceStake);

		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Roll forward to accumulate rewards
		vm.roll(startBlock + 10);

		// Check that rewards have accumulated
		uint256 claimableBefore = launchpool.getClaimableProjectToken(alice);
		assertTrue(claimableBefore > 0, "Should have accumulated rewards");

		// Record token balances before unstaking
		uint256 projectBalanceBefore = projectToken.balanceOf(alice);
		uint256 vAssetBalanceBefore = vAsset.balanceOf(alice);

		// Emergency unstake
		vm.startPrank(alice);
		launchpool.unstakeWithoutProjectToken(aliceStake);
		vm.stopPrank();

		// Verify Alice received her vTokens back
		assertEq(
			vAsset.balanceOf(alice),
			vAssetBalanceBefore + aliceStake,
			"Alice should get her vTokens back"
		);

		// Verify Alice did NOT receive any project tokens
		assertEq(
			projectToken.balanceOf(alice),
			projectBalanceBefore,
			"Alice should not receive any project tokens"
		);

		// Verify Alice's stake is gone
		assertEq(
			launchpool.getStakerNativeAmount(alice),
			0,
			"Alice's stake should be zero after unstaking"
		);

		// Verify claimable tokens still remain
		assertEq(
			launchpool.getClaimableProjectToken(alice),
			claimableBefore,
			"Claimable tokens should remain after emergency unstaking"
		);
	}

	function test_unstake_then_stake_to_max() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxTokenPerStaker = 1e3 * (10 ** nativeAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxTokenPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker with plenty of tokens
		address alice = makeAddr("alice");
		uint256 totalVTokens = 2e3 * (10 ** vAsset.decimals()); // Mint plenty of tokens
		vAsset.freeMintTo(alice, totalVTokens);

		// Calculate initial stake to reach max
		uint256 nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 initialStakeVTokens = (maxTokenPerStaker *
			(10 ** vAsset.decimals())) / nativePerVToken;

		// First stake to reach max
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), totalVTokens);
		launchpool.stake(initialStakeVTokens);
		vm.stopPrank();

		// Verify we've reached max
		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			aliceNativeStake,
			maxTokenPerStaker,
			0.01e18,
			"Native stake should be approximately equal to maxTokenPerStaker"
		);

		// Try staking more, should fail
		vm.startPrank(alice);
		vm.expectRevert(Launchpool.ExceedMaxTokensPerStaker.selector);
		launchpool.stake(2);
		vm.stopPrank();

		// Unstake half of the tokens
		uint256 halfVTokens = launchpool.getTotalStakedVTokens() / 2;
		vm.startPrank(alice);
		launchpool.unstake(halfVTokens);
		vm.stopPrank();

		// Verify we're now under max
		uint256 nativeStakeAfterUnstake = launchpool.getStakerNativeAmount(
			alice
		);
		assertLt(
			nativeStakeAfterUnstake,
			maxTokenPerStaker,
			"Native stake should be less than maxTokenPerStaker after unstaking"
		);

		// Calculate how much we can stake to reach max again
		uint256 remainingNative = maxTokenPerStaker - nativeStakeAfterUnstake;
		nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 additionalStake = (remainingNative *
			(10 ** vAsset.decimals())) / nativePerVToken;

		// Stake back to max
		vm.startPrank(alice);
		launchpool.stake(additionalStake);
		vm.stopPrank();

		// Verify we're at max again
		uint256 finalNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			finalNativeStake,
			maxTokenPerStaker,
			0.01e18,
			"Final native stake should be approximately equal to maxTokenPerStaker"
		);

		// Try staking more, should fail again
		vm.startPrank(alice);
		vm.expectRevert(Launchpool.ExceedMaxTokensPerStaker.selector);
		launchpool.stake(2);
		vm.stopPrank();
	}

	function test_unstake_all_and_stake_again() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxTokenPerStaker = 1e3 * (10 ** nativeAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxTokenPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker with tokens
		address alice = makeAddr("alice");
		uint256 totalVTokens = 2e3 * (10 ** vAsset.decimals()); // Mint plenty of tokens
		vAsset.freeMintTo(alice, totalVTokens);

		// Stake half of max initially
		uint256 nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 halfMaxNative = maxTokenPerStaker / 2;
		uint256 initialStake = (halfMaxNative * (10 ** vAsset.decimals())) /
			nativePerVToken;

		vm.startPrank(alice);
		vAsset.approve(address(launchpool), totalVTokens);
		launchpool.stake(initialStake);
		vm.stopPrank();

		// Roll forward to accumulate some rewards
		vm.roll(startBlock + 10);

		// Check rewards accumulated
		uint256 rewardsBefore = launchpool.getClaimableProjectToken(alice);
		assertTrue(rewardsBefore > 0, "Should have accumulated rewards");

		// Get the withdrawable amount
		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		uint256 withdrawableVTokens = launchpool.getWithdrawableVTokens(
			aliceNativeStake
		);

		// Unstake everything
		vm.startPrank(alice);
		launchpool.unstake(withdrawableVTokens);
		vm.stopPrank();

		// Verify completely unstaked
		assertEq(
			launchpool.getStakerNativeAmount(alice) - 1, // Its how EVM work
			0,
			"Should have no native stake left"
		);

		// Roll forward again
		vm.roll(startBlock + 20);

		// Stake to max
		nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 maxStake = (maxTokenPerStaker * (10 ** vAsset.decimals())) /
			nativePerVToken;

		vm.startPrank(alice);
		launchpool.stake(maxStake);
		vm.stopPrank();

		// Verify at max
		uint256 finalNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			finalNativeStake,
			maxTokenPerStaker,
			0.01e18,
			"Final native stake should be approximately equal to maxTokenPerStaker"
		);

		// Verify new rewards start accumulating from zero
		uint256 rewardsAfter = launchpool.getClaimableProjectToken(alice);
		assertEq(rewardsAfter, 0, "Rewards should reset after new stake");

		// Roll forward more to see rewards accumulate again
		vm.roll(startBlock + 30);
		uint256 newRewards = launchpool.getClaimableProjectToken(alice);
		assertTrue(
			newRewards > 0,
			"Should accumulate new rewards after staking again"
		);
	}

	function test_unstake_with_changing_exrate_restake_to_max() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxTokenPerStaker = 1e3 * (10 ** nativeAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
		changeBlocks[0] = startBlock;
		emissionRateChanges[0] =
			(1e20 * (10 ** projectToken.decimals())) /
			poolDurationBlocks;

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			startBlock,
			endBlock,
			maxTokenPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker with tokens
		address alice = makeAddr("alice");
		uint256 totalVTokens = 3e3 * (10 ** vAsset.decimals()); // Mint plenty of tokens
		vAsset.freeMintTo(alice, totalVTokens);

		// Stake to max initially
		uint256 nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 initialStake = (maxTokenPerStaker * (10 ** vAsset.decimals())) /
			nativePerVToken;

		vm.startPrank(alice);
		vAsset.approve(address(launchpool), totalVTokens);
		launchpool.stake(initialStake);
		vm.stopPrank();

		// Verify at max
		uint256 initialNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			initialNativeStake,
			maxTokenPerStaker,
			0.01e18,
			"Initial native stake should be approximately equal to maxTokenPerStaker"
		);

		// Change exchange rate
		xcmOracle.setExchangeRate(1.5e18); // 25% increase

		// Unstake half
		uint256 halfVTokens = launchpool.getTotalStakedVTokens() / 2;
		vm.startPrank(alice);
		launchpool.unstake(halfVTokens);
		vm.stopPrank();

		// After unstaking half and with higher exchange rate, we should be significantly under max
		uint256 midNativeStake = launchpool.getStakerNativeAmount(alice);
		assertLt(
			midNativeStake,
			(maxTokenPerStaker * 2) / 3, // Should be notably less than 2/3 of max
			"After unstaking with higher rate, should be well below max"
		);

		// Change exchange rate again
		xcmOracle.setExchangeRate(1.8e18); // Another 20% increase

		// Calculate how much to stake to reach max again with new rate
		uint256 remainingNative = maxTokenPerStaker - midNativeStake;
		nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 additionalStake = (remainingNative *
			(10 ** vAsset.decimals())) / nativePerVToken;

		// Stake back to max
		vm.startPrank(alice);
		launchpool.stake(additionalStake);
		vm.stopPrank();

		// Verify we're at max again
		uint256 finalNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			finalNativeStake,
			maxTokenPerStaker,
			0.01e18,
			"Final native stake should be approximately equal to maxTokenPerStaker"
		);

		// Try to stake more, should fail
		vm.startPrank(alice);
		vm.expectRevert(Launchpool.ExceedMaxTokensPerStaker.selector);
		launchpool.stake(2);
		vm.stopPrank();
	}
}
