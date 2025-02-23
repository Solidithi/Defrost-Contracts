// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "../mocks/MockLaunchpool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract UnstakeTest is Test {
	MockLaunchpool public launchpool;
	MockERC20 public projectToken;
	MockERC20 public vAsset;
	uint256 constant BLOCK_TIME = 6 seconds;

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");
	}

	function testUnstakeSuccess() public {
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

		vm.roll(endBlock);
		(uint256 vAssetAmount, , ) = launchpool.stakers(address(this));
		// uint256 claimableProjectTokenAmount = launchpool.getClaimableProjectToken(address(this));
		

		launchpool.unstake(stakeAmount);

		assertEq(vAssetAmount, stakeAmount);
		// assertEq(, claimableProjectTokenAmount); //Check received project token amouunt

		
	}

	
}