// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "../mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { MockXCMOracle } from "../mocks/MockXCMOracle.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract UnstakeTest is Test {
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	MockXCMOracle xcmOracle;
	MockLaunchpool launchpool;

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
		nativeAsset = new MockERC20("Native Imaginary", "nImaginary");
		xcmOracle = new MockXCMOracle();
	}

	function test_unstake_success() public {
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
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
		uint256 aliceUnstake = xcmOracle.getVTokenByToken(
			address(nativeAsset),
			aliceStake
		);

		vm.startPrank(alice);
		launchpool.unstake(aliceUnstake);
		vm.stopPrank();

		// Assert
		uint256 aliceClaimable = launchpool.getClaimableProjectToken(alice);
		assertEq(aliceClaimable, 0);

		uint256 aliceVAssetBalance = vAsset.balanceOf(alice);
		assertTrue(aliceVAssetBalance <= maxVTokensPerStaker);

		uint256 aliceNativeBalance = xcmOracle.getTokenByVToken(
			address(nativeAsset),
			aliceVAssetBalance
		);

		assertEq(aliceNativeBalance, aliceStake);
	}

	function test_unstake_more_than_staked() public {
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
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
		uint256 alicePossibleUnstake = xcmOracle.getVTokenByToken(
			address(nativeAsset),
			aliceStake
		);

		vm.startPrank(alice);
		vm.expectRevert(Launchpool.VAssetAmountNotSufficient.selector);
		launchpool.unstake(alicePossibleUnstake * 2);
		vm.stopPrank();
	}

	function test_unstake_before_end() public {
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
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
		uint256 alicePossibleUnstake = xcmOracle.getVTokenByToken(
			address(nativeAsset),
			aliceStake
		);

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
		changeBlocks[0] = 0;
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());
		uint128 endBlock = startBlock + poolDurationBlocks;
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
		uint256 totalVAssetToUnstake = xcmOracle.getVTokenByToken(
			address(nativeAsset),
			totalStaked
		);

		uint256 unstakeAmount = totalVAssetToUnstake / 5;

		vm.startPrank(alice);
		launchpool.unstake(unstakeAmount);
		vm.roll(endBlock);
		launchpool.unstake(unstakeAmount);
		assertTrue(true);
	}
}
