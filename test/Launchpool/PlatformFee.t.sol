// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { DeployMockXCMOracle } from "test/testutils/DeployMockXCMOracle.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract PlatformFeeTest is Test {
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
	uint128 public poolDurationBlocks = END_BLOCK - START_BLOCK;

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

		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

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

		vm.roll(START_BLOCK);

		// Mint tokens for testing
		projectToken.freeMintTo(address(launchpool), 1000 ether);
		vAsset.freeMintTo(address(this), 1000 ether);
		nativeAsset.freeMintTo(address(this), 1000 ether);

		// Approve tokens for the launchpool
		vAsset.approve(address(launchpool), type(uint256).max);
		nativeAsset.approve(address(launchpool), type(uint256).max);
	}

	function test_initial_platform_fee_claimed_status() public view {
		assertEq(
			launchpool.platformFeeClaimed(),
			false,
			"Platform fee should not be claimed initially"
		);
	}

	function test_claim_success() public {
		assert(launchpool.platformAdminAddress() != launchpool.owner());

		// Simulate staking
		address staker1 = makeAddr("staker1");
		address staker2 = makeAddr("staker2");
		vAsset.freeMintTo(staker1, MAX_VSTAKER);
		vAsset.freeMintTo(staker2, MAX_VSTAKER);

		// Staker 1 stakes
		vm.roll(START_BLOCK);
		vm.startPrank(staker1);
		uint256 staker1VAmount = MAX_VSTAKER / 2;
		vAsset.approve(address(launchpool), staker1VAmount);
		launchpool.stake(staker1VAmount);
		vm.stopPrank();

		// Staker 2 stakes
		vm.roll(START_BLOCK + (poolDurationBlocks * 2) / 3);
		vm.startPrank(staker2);
		uint256 staker2VAmount = MAX_VSTAKER / 4;
		vAsset.approve(address(launchpool), staker2VAmount);
		launchpool.stake(staker2VAmount);
		vm.stopPrank();

		assertEq(
			launchpool.getTotalStakedVTokens(),
			staker1VAmount + staker2VAmount,
			"Total staked vAssets should be sum of staker 1 and staker 2"
		);

		// Expect revert if attempt to claim before pool end
		vm.roll(END_BLOCK);
		console.log(
			"Actual exrate at end block %d",
			launchpool.exposed_getTokenByVTokenWithoutFee(
				10 ** vAsset.decimals()
			)
		);

		address platformAdmin = launchpool.platformAdminAddress();
		vm.expectRevert(
			abi.encodeWithSelector(Launchpool.MustBeAfterPoolEnd.selector)
		);
		vm.prank(platformAdmin);
		launchpool.claimPlatformFee();

		// Snapshot state variables before action
		uint256 poolBalanceBefore = vAsset.balanceOf(address(launchpool));
		uint256 platformBalanceBefore = vAsset.balanceOf(platformAdmin);
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		(uint256 ownerClaims, uint256 platformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();
		console.log("Platform fee amount in test: %d", platformFee);

		// Perform claim
		vm.roll(END_BLOCK + 1);
		console.log(
			"Estimated native exrate at end: %d",
			launchpool.exposed_getEstimatedNativeExRateAtEnd()
		);
		vm.startPrank(platformAdmin);
		launchpool.claimPlatformFee();
		vm.stopPrank();

		// Assert
		assertEq(
			launchpool.platformFeeClaimed(),
			true,
			"Platform fee should be claimed after calling claimPlatformFee"
		);
		assertEq(
			vAsset.balanceOf(platformAdmin),
			platformBalanceBefore + platformFee,
			"Platform admin should receive claimed vAssets"
		);

		assertEq(
			vAsset.balanceOf(address(launchpool)),
			poolBalanceBefore - platformFee,
			"Pool balance should decrease by claimed amount"
		);

		assertEq(
			vAsset.balanceOf(owner),
			ownerBalanceBefore,
			"Owner balance should not change"
		);

		(uint256 newOwnerClaims, uint256 newPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();

		assertEq(
			newPlatformFee,
			0,
			"Platform and owner claimable vAssets should be zero after claiming"
		);

		assertEq(
			newOwnerClaims,
			ownerClaims,
			"Owner claim should stay the same"
		);
	}

	function test_revert_already_claimed() public {
		// Simulate staking
		address staker1 = makeAddr("staker1");
		address staker2 = makeAddr("staker2");
		vAsset.freeMintTo(staker1, MAX_VSTAKER);
		vAsset.freeMintTo(staker2, MAX_VSTAKER);

		// Staker 1 stakes
		vm.roll(START_BLOCK);
		vm.startPrank(staker1);
		uint256 staker1VAmount = MAX_VSTAKER / 2;
		vAsset.approve(address(launchpool), staker1VAmount);
		launchpool.stake(staker1VAmount);
		vm.stopPrank();

		// Staker 2 stakes
		vm.roll(START_BLOCK + (poolDurationBlocks * 2) / 3);
		vm.startPrank(staker2);
		uint256 staker2VAmount = MAX_VSTAKER / 4;
		vAsset.approve(address(launchpool), staker2VAmount);
		launchpool.stake(staker2VAmount);
		vm.stopPrank();

		assertEq(
			launchpool.getTotalStakedVTokens(),
			staker1VAmount + staker2VAmount,
			"Total staked vAssets should be sum of staker 1 and staker 2"
		);

		// Claim platform fee
		vm.roll(END_BLOCK + 10000);
		vm.startPrank(launchpool.platformAdminAddress());
		launchpool.claimPlatformFee();
		vm.stopPrank();

		// Expect revert if attempt to claim again
		vm.startPrank(launchpool.platformAdminAddress());
		vm.expectRevert(
			abi.encodeWithSelector(
				Launchpool.PlatformFeeAlreadyClaimed.selector
			)
		);
		launchpool.claimPlatformFee();
		vm.stopPrank();
	}
}
