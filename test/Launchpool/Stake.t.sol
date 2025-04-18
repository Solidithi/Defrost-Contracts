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

contract StakeTest is Test {
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

	function test_basic_stake() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker
		address alice = makeAddr("alice");
		uint256 aliceStake = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(alice, aliceStake);

		// Stake
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Assertions
		assertEq(
			vAsset.balanceOf(alice),
			0,
			"Alice's vAsset balance should be 0 after staking"
		);
		assertEq(
			vAsset.balanceOf(address(launchpool)),
			aliceStake,
			"Launchpool's vAsset balance should equal the staked amount"
		);

		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		uint256 expectedNativeAmount = launchpool
			.exposed_getTokenByVTokenWithoutFee(aliceStake);
		assertEq(
			aliceNativeStake,
			expectedNativeAmount,
			"Alice's native stake should match the converted amount"
		);

		assertEq(
			launchpool.totalNativeStake(),
			expectedNativeAmount,
			"Total native stake should match Alice's stake"
		);
	}

	function test_stake_multiple_users() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare stakers
		address alice = makeAddr("alice");
		address bob = makeAddr("bob");

		uint256 aliceStake = maxVTokensPerStaker / 2;
		uint256 bobStake = maxVTokensPerStaker / 4;

		vAsset.freeMintTo(alice, aliceStake);
		vAsset.freeMintTo(bob, bobStake);

		// Alice stakes
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Record Alice's native stake
		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);

		// Bob stakes
		vm.startPrank(bob);
		vAsset.approve(address(launchpool), bobStake);
		launchpool.stake(bobStake);
		vm.stopPrank();

		// Record Bob's native stake
		uint256 bobNativeStake = launchpool.getStakerNativeAmount(bob);

		// Assertions
		assertEq(
			vAsset.balanceOf(alice),
			0,
			"Alice's vAsset balance should be 0 after staking"
		);
		assertEq(
			vAsset.balanceOf(bob),
			0,
			"Bob's vAsset balance should be 0 after staking"
		);
		assertEq(
			vAsset.balanceOf(address(launchpool)),
			aliceStake + bobStake,
			"Launchpool's vAsset balance should equal the total staked amount"
		);

		assertEq(
			launchpool.totalNativeStake(),
			aliceNativeStake + bobNativeStake,
			"Total native stake should match sum of Alice and Bob stakes"
		);
	}

	function test_stake_zero_amount() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker
		address alice = makeAddr("alice");
		vAsset.freeMintTo(alice, 100);

		// Attempt to stake zero amount
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), 100);

		// Should revert with ZeroAmountNotAllowed
		vm.expectRevert(Launchpool.ZeroAmountNotAllowed.selector);
		launchpool.stake(0);
		vm.stopPrank();
	}

	function test_stake_outside_pool_time() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 10;
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

		// Prepare staker
		address alice = makeAddr("alice");
		uint256 aliceStake = maxVTokensPerStaker / 2;
		vAsset.freeMintTo(alice, aliceStake);

		// Attempt to stake before start block
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);

		// Should revert with MustBeDuringPoolTime
		vm.expectRevert(Launchpool.MustBeDuringPoolTime.selector);
		launchpool.stake(aliceStake);

		// Move to after end block
		vm.roll(endBlock + 1);

		// Should still revert with MustBeDuringPoolTime
		vm.expectRevert(Launchpool.MustBeDuringPoolTime.selector);
		launchpool.stake(aliceStake);
		vm.stopPrank();
	}

	function test_stake_multiple_times() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker
		address alice = makeAddr("alice");
		uint256 firstStake = maxVTokensPerStaker / 4;
		uint256 secondStake = maxVTokensPerStaker / 4;
		vAsset.freeMintTo(alice, firstStake + secondStake);

		// First stake
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), firstStake + secondStake);
		launchpool.stake(firstStake);

		// Move forward a few blocks to accumulate rewards
		vm.roll(startBlock + 10);

		// Check claimable tokens after some blocks
		uint256 claimableBefore = launchpool.getClaimableProjectToken(alice);
		assertTrue(
			claimableBefore > 0,
			"Should have accumulated some project tokens"
		);

		// Second stake - should claim accumulated rewards first
		uint256 projectTokenBalanceBefore = projectToken.balanceOf(alice);
		launchpool.stake(secondStake);
		uint256 projectTokenBalanceAfter = projectToken.balanceOf(alice);
		vm.stopPrank();

		// Assertions
		assertEq(
			projectTokenBalanceAfter - projectTokenBalanceBefore,
			claimableBefore,
			"Should receive accumulated project tokens"
		);
		assertEq(
			vAsset.balanceOf(alice),
			0,
			"Alice's vAsset balance should be 0 after staking twice"
		);
		assertEq(
			vAsset.balanceOf(address(launchpool)),
			firstStake + secondStake,
			"Launchpool should have received both stake amounts"
		);

		// Check accumulated rewards were reset
		uint256 claimableAfter = launchpool.getClaimableProjectToken(alice);
		assertEq(
			claimableAfter,
			0,
			"Claimable tokens should be reset after claiming during second stake"
		);
	}

	function test_stake_with_exchange_rate_change() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare stakers
		address alice = makeAddr("alice");
		address bob = makeAddr("bob");

		uint256 aliceStake = maxVTokensPerStaker / 4;
		uint256 bobStake = maxVTokensPerStaker / 4;

		vAsset.freeMintTo(alice, aliceStake);
		vAsset.freeMintTo(bob, bobStake);

		// Alice stakes at initial exchange rate
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);

		// Change exchange rate
		xcmOracle.setExchangeRate(1.5e18); // 25% increase

		// Bob stakes at new exchange rate
		vm.startPrank(bob);
		vAsset.approve(address(launchpool), bobStake);
		launchpool.stake(bobStake);
		vm.stopPrank();

		uint256 bobNativeStake = launchpool.getStakerNativeAmount(bob);

		// Assertions
		assertTrue(
			bobNativeStake > aliceNativeStake,
			"Bob's native stake should be higher due to increased exchange rate"
		);
		assertApproxEqRel(
			bobNativeStake,
			(aliceNativeStake * 5) / 4,
			0.01e18,
			"Bob's native stake should be approximately 25% higher than Alice's"
		);

		// Ensure total native stake is sum of individual stakes
		assertEq(
			launchpool.totalNativeStake(),
			aliceNativeStake + bobNativeStake,
			"Total native stake should be sum of individual stakes"
		);
	}

	function test_stake_more_than_max() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker with amount exactly equal to max + 1
		address alice = makeAddr("alice");
		uint256 aliceStake = maxVTokensPerStaker + 1;
		vAsset.freeMintTo(alice, aliceStake);

		// Attempt to stake more than the maximum
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);

		// Expect revert with ExceedMaxTokensPerStaker
		vm.expectRevert(Launchpool.ExceedMaxTokensPerStaker.selector);
		launchpool.stake(aliceStake);
		vm.stopPrank();
	}

	function test_stack_stake_reach_more_than_max() public {
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

		// Move to start block
		vm.roll(startBlock);

		// Prepare staker
		address alice = makeAddr("alice");
		uint256 firstStake = maxVTokensPerStaker / 2;
		uint256 secondStake = maxVTokensPerStaker / 2 + 1; // This will exceed max when combined
		vAsset.freeMintTo(alice, firstStake + secondStake);

		// First stake - should succeed
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), firstStake + secondStake);
		launchpool.stake(firstStake);

		// Second stake - should fail because it would exceed max
		vm.expectRevert(Launchpool.ExceedMaxTokensPerStaker.selector);
		launchpool.stake(secondStake);
		vm.stopPrank();

		// Verify first stake was successful
		assertEq(
			vAsset.balanceOf(address(launchpool)),
			firstStake,
			"Launchpool should have received only the first stake"
		);
	}

	function test_stake_with_exact_max() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxNativeTokensPerStaker = 1e3 * (10 ** nativeAsset.decimals());
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
			maxNativeTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Move to start block
		vm.roll(startBlock);

		// Calculate the vToken amount that would convert to exactly maxNativeTokensPerStaker
		uint256 nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 aliceStake = (maxNativeTokensPerStaker *
			(10 ** vAsset.decimals())) / nativePerVToken;

		// Prepare staker with amount that will convert to exactly max native tokens
		address alice = makeAddr("alice");
		vAsset.freeMintTo(alice, aliceStake);

		// Attempt to stake exactly the maximum (in native token equivalent)
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// Assertions
		assertEq(
			vAsset.balanceOf(alice),
			0,
			"Alice's vAsset balance should be 0 after staking"
		);
		assertEq(
			vAsset.balanceOf(address(launchpool)),
			aliceStake,
			"Launchpool's vAsset balance should equal the staked amount"
		);

		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			aliceNativeStake,
			maxNativeTokensPerStaker,
			0.01e18,
			"Alice's native stake should be approximately equal to maxNativeTokensPerStaker"
		);
	}

	function test_stack_stake_with_exact_max() public {
		uint128[] memory changeBlocks = new uint128[](1);
		uint256[] memory emissionRateChanges = new uint256[](1);
		uint128 poolDurationBlocks = 70;
		uint128 startBlock = uint128(block.number) + 1;
		uint256 maxNativeTokensPerStaker = 1e3 * (10 ** nativeAsset.decimals());
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
			maxNativeTokensPerStaker,
			changeBlocks,
			emissionRateChanges
		);

		projectToken.transfer(
			address(launchpool),
			1e20 * (10 ** projectToken.decimals())
		);

		// Move to start block
		vm.roll(startBlock);

		// Calculate the vToken amount that would convert to exactly maxNativeTokensPerStaker
		uint256 nativePerVToken = launchpool.exposed_getTokenByVTokenWithoutFee(
			10 ** vAsset.decimals()
		);
		uint256 aliceStake = (maxNativeTokensPerStaker *
			(10 ** vAsset.decimals())) / nativePerVToken;

		// Prepare staker with amount that will convert to exactly max native tokens
		address alice = makeAddr("alice");
		vAsset.freeMintTo(alice, aliceStake);

		// Attempt to stake exactly the maximum (in native token equivalent)
		vm.startPrank(alice);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake / 2);
		launchpool.stake(aliceStake / 2 + 1); // Don't ask
		vm.stopPrank();

		// Assertions
		assertEq(
			vAsset.balanceOf(alice),
			0,
			"Alice's vAsset balance should be 0 after staking"
		);
		assertEq(
			vAsset.balanceOf(address(launchpool)),
			aliceStake,
			"Launchpool's vAsset balance should equal the staked amount"
		);

		uint256 aliceNativeStake = launchpool.getStakerNativeAmount(alice);
		assertApproxEqRel(
			aliceNativeStake,
			maxNativeTokensPerStaker,
			0.01e18,
			"Alice's native stake should be approximately equal to maxNativeTokensPerStaker"
		);
	}
}
