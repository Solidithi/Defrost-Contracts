// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "../mocks/MockLaunchpool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

// @todo: Improve testcase later on when implementation for valid vAsset
contract GeneralGetterFuncsTest is Test {
	// Default pool init values, use different values in test cases if needed
	MockERC20 public projectToken = new MockERC20("PROJECT", "PRO");
	MockERC20 public vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
	MockLaunchpool public launchpool;
	uint128[] changeBlocks = new uint128[](1);
	uint256[] emissionRateChanges = new uint256[](1);
	uint256 public constant BLOCK_TIME = 6 seconds;
	uint128 poolDurationBlocks = 70;
	uint128 startBlock = uint128(block.number) + 1;
	uint128 endBlock = startBlock + poolDurationBlocks;
	uint256 maxVAssetPerStaker = 1e4 * (10 ** vAsset.decimals());
	uint256 maxStakers = 0;

	constructor() {
		changeBlocks[0] = 0;
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
	}

	function setUp() public {
		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			startBlock,
			endBlock,
			maxVAssetPerStaker,
			changeBlocks,
			emissionRateChanges
		);
	}

	function testGetTotalStaked() public {
		// Act: Stake vTokens at pool start
		uint256 stakeAmount = maxVAssetPerStaker - 1;
		vAsset.approve(address(launchpool), stakeAmount);
		launchpool.stake(stakeAmount);

		// Assert: Check total staked amount
		uint256 retrievedStakeAmount = launchpool.getTotalStaked();
		assertEq(
			retrievedStakeAmount,
			stakeAmount,
			"Total staked amount is not correct"
		);

		// Act 2: Stake vTokens at half of pool duration
		uint256 stakeAmount2 = (maxVAssetPerStaker * 6) / 7;
		vAsset.approve(address(launchpool), stakeAmount2);
		launchpool.stake(stakeAmount2);

		// Assert 2: Check total staked amount
		retrievedStakeAmount = launchpool.getTotalStaked();
		assertEq(
			retrievedStakeAmount,
			stakeAmount + stakeAmount2,
			"Total staked amount is not correct after staking twice"
		);
	}

	function testGetEmissionRate() public {
		// Arrange: Set up a new launchpool with multiple rate changes
		uint128[] memory _changeBlocks = new uint128[](3);
		uint256[] memory _emissionRates = new uint256[](3);

		_changeBlocks[0] = startBlock;
		_changeBlocks[1] = startBlock + poolDurationBlocks / 2;
		_changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4;

		_emissionRates[0] = 1000 * (10 ** vAsset.decimals());
		_emissionRates[1] = 500 * (10 ** vAsset.decimals());
		_emissionRates[2] = 250 * (10 ** vAsset.decimals());

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			startBlock,
			endBlock,
			maxVAssetPerStaker,
			_changeBlocks,
			_emissionRates
		);

		// Test initial emission rate
		vm.roll(startBlock);
		assertEq(
			launchpool.getEmissionRate(),
			_emissionRates[0],
			"Initial emission rate incorrect"
		);

		// Test rate at first change block
		vm.roll(_changeBlocks[1]);
		assertEq(
			launchpool.getEmissionRate(),
			_emissionRates[1],
			"Emission rate after first change incorrect"
		);

		// Test rate at second change block
		vm.roll(_changeBlocks[2]);
		assertEq(
			launchpool.getEmissionRate(),
			_emissionRates[2],
			"Emission rate after second change incorrect"
		);

		// Test rate between change blocks
		vm.roll(_changeBlocks[1] + 1);
		assertEq(
			launchpool.getEmissionRate(),
			_emissionRates[1],
			"Emission rate between changes incorrect"
		);

		// Test rate at end block
		vm.roll(endBlock);
		assertEq(
			launchpool.getEmissionRate(),
			0,
			"Emission rate at end block should be 0"
		);

		// Test rate after end block
		vm.roll(endBlock + 1);
		assertEq(
			launchpool.getEmissionRate(),
			0,
			"Emission rate after end block should be 0"
		);
	}

	function testGetPoolInfo() public {
		// Act:
		// Deposit project tokens into the pool
		uint256 depositAmount = projectToken.balanceOf(address(this));
		projectToken.transfer(address(launchpool), depositAmount);

		// Assert:
		(
			uint256 _startBlock,
			uint256 _endBlock,
			uint256 _totalProjectToken,
			uint256 _emissionRate
		) = launchpool.getPoolInfo();
		assertEq(
			_startBlock,
			startBlock,
			"Start block is not identical to that passed into constructor"
		);
		assertEq(
			_endBlock,
			endBlock,
			"End block is not identical to that passed into constructor"
		);
		assertEq(
			_totalProjectToken,
			depositAmount,
			"Total project token is not identical to the amount deposited into the launchpool"
		);
		assertEq(
			_emissionRate,
			emissionRateChanges[0],
			"Emission rate is not identical to that passed into constructor"
		);
	}

	function testGetTotalProjectToken() public {
		// Act: Deposit project tokens to launchpool
		uint256 depositAmount = projectToken.balanceOf(address(this));
		projectToken.transfer(address(launchpool), depositAmount);

		// Assert: Check launchpool's project token balance
		uint256 projectTokenBalance = launchpool.getTotalProjectToken();
		assertEq(
			projectTokenBalance,
			depositAmount,
			"Total project token balance is not correct"
		);
	}

	function testGetStakingRange() public {
		// Assert:
		(uint256 _maxVAssetPerStaker, uint256 _maxStakers) = launchpool
			.getStakingRange();

		assertEq(
			_maxVAssetPerStaker,
			maxVAssetPerStaker,
			"Max vAsset per staker is not correct"
		);
		assertEq(_maxStakers, maxStakers, "Max stakers is not correct");
	}

	function testGetClaimableProjectToken() public {
		// Arrange: Set up a new launchpool with multiple rate changes
		uint128 _poolDurationBlocks = uint128(21 days / BLOCK_TIME);
		uint128 _startBlock = uint128(block.number) + 1;
		uint128 _endBlock = _startBlock + _poolDurationBlocks;

		uint128[] memory _changeBlocks = new uint128[](4);
		uint256[] memory _emissionRates = new uint256[](4);

		_changeBlocks[0] = _startBlock;
		_changeBlocks[1] = _startBlock + _poolDurationBlocks / 2;
		_changeBlocks[2] = _startBlock + (_poolDurationBlocks * 3) / 4;
		_changeBlocks[3] = _startBlock + (_poolDurationBlocks * 9) / 10;

		_emissionRates[0] = 1000 * (10 ** vAsset.decimals());
		_emissionRates[1] = 500 * (10 ** vAsset.decimals());
		_emissionRates[2] = 250 * (10 ** vAsset.decimals());
		_emissionRates[3] = 100 * (10 ** vAsset.decimals());

		launchpool = new MockLaunchpool(
			address(this),
			address(projectToken),
			address(vAsset),
			_startBlock,
			_endBlock,
			maxVAssetPerStaker,
			_changeBlocks,
			_emissionRates
		);

		uint256 projectTokenBalance = projectToken.balanceOf(address(this));
		projectToken.transfer(address(launchpool), projectTokenBalance);

		// Create actors with different addresses
		address alice = makeAddr("alice");
		address bob = makeAddr("bob");
		address dave = makeAddr("dave");

		// Act:
		// 1. Alice stakes 1e4 vTokens at pool start + 100 blocks
		vm.roll(_startBlock + 100);
		vm.startPrank(alice);
		uint256 aliceStake = 1e4 * (10 ** vAsset.decimals());
		vAsset.freeMint(aliceStake);
		vAsset.approve(address(launchpool), aliceStake);
		launchpool.stake(aliceStake);
		vm.stopPrank();

		// 2. Bob stakes 1 vToken at the block after 2nd change block
		vm.roll(_changeBlocks[2] + 1);
		vm.startPrank(bob);
		uint256 bobStake = 1 * (10 ** vAsset.decimals());
		vAsset.freeMint(bobStake);
		vAsset.approve(address(launchpool), bobStake);
		launchpool.stake(bobStake);
		vm.stopPrank();

		// 3. Dave stakes another 1e4 vTokens at the block before 3rd change block
		vm.roll(_changeBlocks[3] - 1);
		vm.startPrank(dave); // Fixed: Use alice's prank instead of bob's
		uint256 daveStake = 1e4 * (10 ** vAsset.decimals()); // Fixed: Use 1e4 instead of 1
		vAsset.freeMint(daveStake);
		vAsset.approve(address(launchpool), daveStake);
		launchpool.stake(daveStake);
		vm.stopPrank();

		// Assert:
		// 1. Check claimable project token amount for Alice at end of pool
		vm.roll(_endBlock);
		uint256 actualAliceClaimables = launchpool.getClaimableProjectToken(
			alice
		);

		// Calculate expected claimable project token amount for Alice
		uint256 period1Blocks = _changeBlocks[1] - (_startBlock + 100);
		uint256 period1ExchangeRate = (_emissionRates[0] * period1Blocks) /
			aliceStake;

		uint256 period2Blocks = _changeBlocks[2] - _changeBlocks[1];
		uint256 period2ExchangeRate = (_emissionRates[1] * period2Blocks) /
			aliceStake;

		uint256 period3Blocks = 1;
		uint256 period3ExchangeRate = (_emissionRates[2] * period3Blocks) /
			aliceStake;

		// Bob joins here
		uint256 period4Blocks = _changeBlocks[3] - 1 - (_changeBlocks[2] + 1);
		uint256 period4ExchangeRate = (_emissionRates[2] * period4Blocks) /
			(aliceStake + bobStake);

		// Dave joins here
		uint256 period5Blocks = 1;
		uint256 period5ExchangeRate = (_emissionRates[2] * period5Blocks) /
			(aliceStake + daveStake + bobStake);

		uint256 period6Blocks = _endBlock - _changeBlocks[3];
		uint256 period6ExchangeRate = (_emissionRates[3] * period6Blocks) /
			(aliceStake + daveStake + bobStake);

		uint256 expectedAliceClaimables = (period1ExchangeRate +
			period2ExchangeRate +
			period3ExchangeRate +
			period4ExchangeRate +
			period5ExchangeRate +
			period6ExchangeRate) * aliceStake;
		assertEq(
			actualAliceClaimables,
			expectedAliceClaimables,
			"Claimable amount mismatch"
		);
	}
}
