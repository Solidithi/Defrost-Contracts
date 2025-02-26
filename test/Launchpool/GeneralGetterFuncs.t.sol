// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "../mocks/MockLaunchpool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

// @todo: Improve testcase later on when implementation for valid vAsset
contract CumulativeExchangeRateTest is Test {
	// Default pool init values, use different values in test cases if needed
	MockERC20 public projectToken = new MockERC20("PROJECT", "PRO");
	MockERC20 public vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
	MockERC20 public nativeAsset = new MockERC20("Native Imaginary", "nImaginary");
	MockLaunchpool public launchpool;
	uint128[] changeBlocks = new uint128[](1);
	uint256[] emissionRateChanges = new uint256[](1);
	uint128 poolDurationBlocks = 70;
	uint128 startBlock = uint128(block.number) + 1;
	uint128 endBlock = startBlock + poolDurationBlocks;
	uint256 maxVTokensPerStaker = 1e3 * (10 ** vAsset.decimals());

	constructor() {
		changeBlocks[0] = 0;
		emissionRateChanges[0] = 1e4 * (10 ** vAsset.decimals());
	}

	function setUp() public {
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
	}

	function testGetTotalStaked() public {
		// Act: Stake 1000 vTokens at pool start
		uint256 stakeAmount = maxVTokensPerStaker - 1;
		vAsset.approve(address(launchpool), stakeAmount);
		launchpool.stake(stakeAmount);

		// Assert: Check total staked amount
		uint256 retrievedStakeAmount = launchpool.getTotalStaked();
		assertEq(
			retrievedStakeAmount,
			stakeAmount,
			"Total staked amount is not correct"
		);
	}
}
