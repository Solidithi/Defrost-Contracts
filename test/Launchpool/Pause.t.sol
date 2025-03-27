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

contract PauseTest is Test {
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

	function test_initially_not_paused() public view {
		// Assert
		assertEq(
			launchpool.paused(),
			false,
			"Launchpool must not be paused initially"
		);
	}

	function test_pause_success() public {
		address platformAdmin = launchpool.platformAdminAddress();
		vm.prank(platformAdmin);
		launchpool.pause();

		assertEq(launchpool.paused(), true);
	}

	function test_sequential_pause_unpause() public {
		address platformAdmin = launchpool.platformAdminAddress();
		vm.prank(platformAdmin);
		launchpool.pause();

		address investor = makeAddr("investor");
		vm.startPrank(investor);
		vAsset.freeMintTo(investor, MAX_VSTAKER);
		vAsset.approve(address(launchpool), MAX_VSTAKER);

		// Assert
		vm.expectRevert(
			abi.encodeWithSelector(Pausable.EnforcedPause.selector)
		);
		launchpool.stake(MAX_VSTAKER);
		vm.stopPrank();

		// Admin un-pauses, investor is able to stake
		vm.prank(platformAdmin);
		launchpool.unpause();

		// Assert
		assertEq(
			launchpool.paused(),
			false,
			"Launchpool must not be paused after unpausing"
		);

		vm.prank(investor);
		launchpool.stake(MAX_VSTAKER);

		// Admin pauses again, new investor would not be able to stake
		vm.prank(platformAdmin);
		launchpool.pause();
		address newInvestor = makeAddr("newInvestor");
		vm.startPrank(newInvestor);
		vAsset.freeMintTo(newInvestor, MAX_VSTAKER);
		vAsset.approve(address(launchpool), MAX_VSTAKER);

		// Assert
		vm.expectRevert(
			abi.encodeWithSelector(Pausable.EnforcedPause.selector)
		);
		launchpool.stake(MAX_VSTAKER);
	}

	function test_unstake_without_project_token_when_paused() public {
		// Make investor
		address investor = makeAddr("investor");
		vm.startPrank(investor);
		uint256 investorStake = MAX_VSTAKER;
		vAsset.freeMintTo(investor, investorStake);
		vAsset.approve(address(launchpool), investorStake);

		// Stake
		launchpool.stake(investorStake);
		vm.stopPrank();

		address platformAdmin = launchpool.platformAdminAddress();
		vm.prank(platformAdmin);
		launchpool.pause();

		// Unstake
		vm.startPrank(investor);
		vm.roll(START_BLOCK + (poolDurationBlocks * 4) / 5);
		(uint256 investorNativeStake, ) = launchpool.stakers(investor);
		uint256 withdrawableVAsset = launchpool.getWithdrawableVTokens(
			investorNativeStake
		);
		console.log(
			"Withdrawable VAsset manually called: %d",
			withdrawableVAsset
		);

		// Snapshot related state variables before test-withdrawal
		uint256 totalPTokenBefore = launchpool.getTotalProjectToken();
		uint256 totalVAssetStakeBefore = launchpool.getTotalVAssetStaked();
		uint256 totalNativeStakeBefore = launchpool.totalNativeStake();
		uint256 investorVAssetBalanceBefore = vAsset.balanceOf(investor);

		launchpool.unstakeWithoutProjectToken(withdrawableVAsset);
		vm.stopPrank();

		// Assert
		assertEq(
			launchpool.getTotalProjectToken(),
			totalPTokenBefore,
			"Project token balance should not change after emergency withdrawal"
		);

		assertTrue(
			launchpool.totalNativeStake() < totalNativeStakeBefore,
			"Native stake should decrease after emergency withdrawal"
		);

		assertTrue(
			launchpool.getTotalVAssetStaked() < totalVAssetStakeBefore,
			"VAsset stake should decrease after emergency withdrawal"
		);

		assertEq(
			vAsset.balanceOf(investor),
			investorVAssetBalanceBefore + withdrawableVAsset,
			"Investor should receive withdrawable VAsset after emergency withdrawal"
		);
	}
}
