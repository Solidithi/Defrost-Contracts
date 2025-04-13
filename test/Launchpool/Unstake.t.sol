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
		uint256 aliceStake = maxVTokensPerStaker;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);

		vm.stopPrank();
		aliceStake = launchpool.totalNativeStake();

		vm.roll(endBlock);

		// Act: Unstake
		xcmOracle.setExchangeRate(1.3e18);

		uint256 aliceUnstake = launchpool.exposed_getVTokenByTokenWithoutFee(
			aliceStake
		);

		vm.startPrank(alice);
		launchpool.unstake(aliceUnstake);
		vm.stopPrank();

		// Assert
		uint256 aliceClaimable = launchpool.getClaimableProjectToken(alice);
		assertEq(aliceClaimable, 0);

		uint256 aliceVAssetBalance = vAsset.balanceOf(alice);
		console.log("aliceVAssetBalance", aliceVAssetBalance);
		console.log("maxVTokensPerStaker", maxVTokensPerStaker);
		assertTrue(aliceVAssetBalance <= maxVTokensPerStaker);

		uint256 aliceNativeBalance = launchpool
			.exposed_getTokenByVTokenWithoutFee(aliceVAssetBalance);

		assertApproxEqRel(aliceNativeBalance, aliceStake, 0.0001e18);
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
		uint256 aliceStake = maxVTokensPerStaker;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);

		vm.stopPrank();
		aliceStake = launchpool.totalNativeStake();

		vm.roll(endBlock);

		// Assert
		uint256 alicePossibleUnstake = launchpool
			.exposed_getVTokenByTokenWithoutFee(aliceStake);

		vm.startPrank(alice);
		vm.expectRevert(Launchpool.ExceedWithdrawableVTokens.selector);
		launchpool.unstake(alicePossibleUnstake * 2);
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
		uint256 aliceStake = maxVTokensPerStaker;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);

		vm.stopPrank();
		aliceStake = launchpool.totalNativeStake();

		vm.roll(endBlock - 1);

		// Act: Unstake
		uint256 alicePossibleUnstake = launchpool
			.exposed_getVTokenByTokenWithoutFee(aliceStake);

		vm.startPrank(alice);
		launchpool.unstake(alicePossibleUnstake);
		vm.stopPrank();

		// Assert
		uint256 aliceClaimable = launchpool.getClaimableProjectToken(alice);
		assertEq(aliceClaimable, 0);

		uint256 aliceVAssetBalance = vAsset.balanceOf(alice);
		assertTrue(aliceVAssetBalance <= maxVTokensPerStaker);
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
		uint256 aliceStake = maxVTokensPerStaker;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		vm.roll(startBlock + 10);

		// Act: Unstake multiple times in small amounts
		uint256 totalStaked = launchpool.totalNativeStake();
		uint256 totalVAssetToUnstake = launchpool
			.exposed_getVTokenByTokenWithoutFee(totalStaked);

		uint256 unstakeAmount = totalVAssetToUnstake / 5;
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
		vm.startPrank(alice);
		launchpool.unstake(unstakeAmount);
		vm.stopPrank();

		cumulativeUnstaked += unstakeAmount;
		assertEq(
			vAsset.balanceOf(alice),
			initialVAssetBalance + cumulativeUnstaked
		);

		// Third unstake after pool ends
		vm.roll(endBlock);
		vm.startPrank(alice);
		launchpool.unstake(unstakeAmount);
		vm.stopPrank();

		cumulativeUnstaked += unstakeAmount;
		assertEq(
			vAsset.balanceOf(alice),
			initialVAssetBalance + cumulativeUnstaked
		);

		// Verify final balances and state
		uint256 remainingStake = launchpool.getStakerNativeAmount(alice);
		uint256 expectedRemainingNative = totalStaked -
			launchpool.exposed_getTokenByVTokenWithoutFee(cumulativeUnstaked);
		assertApproxEqRel(remainingStake, expectedRemainingNative, 0.0001e18);
	}

	function test_unstake_with_exchange_rate_change() public {
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
		uint256 aliceStake = maxVTokensPerStaker;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		uint256 totalNativeAtStart = launchpool
			.exposed_getTokenByVTokenWithoutFee(aliceStake);

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
		uint256 nativeForHalfVAsset = launchpool
			.exposed_getTokenByVTokenWithoutFee(halfVAssetStaked);

		// The remainingNative should approximately equal the totalNative minus nativeForHalfVAsset
		// With a small margin of error due to rate calculations
		assertApproxEqRel(
			remainingNative,
			totalNativeAtStart - nativeForHalfVAsset,
			0.0001e18
		);
	}

	function test_unstake_without_project_token() public {
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
		uint256 aliceStake = maxVTokensPerStaker;
		vAsset.freeMintTo(alice, aliceStake);
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Progress a few blocks to accumulate rewards
		vm.roll(startBlock + 20);

		// Calculate claimable project tokens before emergency unstake
		uint256 claimableProjectTokensBefore = launchpool
			.getClaimableProjectToken(alice);
		assertTrue(
			claimableProjectTokensBefore > 0,
			"Should have accumulated some project tokens"
		);

		// Perform emergency unstake
		vm.startPrank(alice);
		launchpool.unstakeWithoutProjectToken(aliceStake);
		vm.stopPrank();

		// Verify Alice got the vAssets back
		assertEq(vAsset.balanceOf(alice), aliceStake);

		// Verify Alice forfeited the project tokens
		uint256 claimableProjectTokensAfter = launchpool
			.getClaimableProjectToken(alice);
		assertEq(
			claimableProjectTokensAfter,
			0,
			"Emergency unstake should forfeit project tokens"
		);

		// Verify Alice's stake is completely removed
		assertEq(launchpool.getStakerNativeAmount(alice), 0);
	}
}
