// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "../mocks/MockLaunchpool.sol";
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
            address(nativeAsset),
            startBlock,
            endBlock,
            maxVTokensPerStaker,
            changeBlocks,
            emissionRateChanges
			// address(xcmOracle)
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
        (, uint256 nativeTokenAmount, ) = launchpool.stakers(address(this));
        uint256 claimableVAssetAmount = xcmOracle.getVTokenByToken(
            address(nativeAsset),
            nativeTokenAmount
        );

        // Log values to debug
        console.log("Stake amount:", stakeAmount);
        // console.log("VAsset amount:", vAsset.balanceOf(address(this)));
        console.log("vAset staked token amount in contract:", vAsset.balanceOf(address(launchpool)));
        // console.log("VAsset amount with Decimal:", vAsset.balanceOf(address(this)) / 10 ** vAsset.decimals());
        console.log("Native token amount:", nativeTokenAmount);
        console.log("Claimable vAsset amount:", claimableVAssetAmount);
        console.log("Claimable Project Token: ", launchpool.getClaimableProjectToken(address(this)));
        // console.log("Get token by vToken:", xcmOracle.getTokenByVToken(address(nativeAsset), stakeAmount));

        launchpool.unstake(stakeAmount);

        

        assertTrue(
            stakeAmount * nativeAsset.decimals() > claimableVAssetAmount,
            "Claimable vAsset amount is not less than staked amount"
        );
        // assertEq(, claimableProjectTokenAmount); //Check received project token amount
	}
	//15000000000000000000000 getXCM
    //1000000000000000000000  Stake & Claimable
    //99999999999999999000000000000000000000 vAsset

//Stake amount:               18000000000000000000000
//   VAsset amount:           99999999999999999000
//   Native token amount:     15000000000000000000000
//   Claimable vAsset amount: 1000000000000000000000
//   Get token by vToken:     15000000000000000000000


    function testUnstakeWithExchangeRateChangeSuccess() public {
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
            address(nativeAsset),
            startBlock,
            endBlock,
            maxVTokensPerStaker,
            changeBlocks,
            emissionRateChanges
			// address(xcmOracle)
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

        //Change exchange rate
        xcmOracle.setExchangeRate(20);
        

        vm.roll(endBlock);
        (, uint256 nativeTokenAmount, ) = launchpool.stakers(address(this));
        uint256 claimableVAssetAmount = xcmOracle.getVTokenByToken(
            address(nativeAsset),
            nativeTokenAmount
        );

        // Log values to debug
        console.log("Stake amount:", stakeAmount);
        // console.log("VAsset amount:", vAsset.balanceOf(address(this)));
        console.log("vAset staked token amount in contract:", vAsset.balanceOf(address(launchpool)));
        // console.log("VAsset amount with Decimal:", vAsset.balanceOf(address(this)) / 10 ** vAsset.decimals());
        console.log("Native token amount:", nativeTokenAmount);
        console.log("Claimable vAsset amount:", claimableVAssetAmount);
        // console.log("Get token by vToken:", xcmOracle.getTokenByVToken(address(nativeAsset), stakeAmount));

        launchpool.unstake(stakeAmount);

        

        assertTrue(
            stakeAmount * nativeAsset.decimals() > claimableVAssetAmount,
            "Claimable vAsset amount is not less than staked amount"
        );
        // assertEq(, claimableProjectTokenAmount); //Check received project token amount
	}

}