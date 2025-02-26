// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MoonbeamLaunchpoolFactory } from "../../src/MoonbeamLPFactory.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";

contract CreateLaunchPoolTest is Test {
	MoonbeamLaunchpoolFactory public poolFactory;
	MockERC20 public projectToken;

	IERC20 vDOT = IERC20(0xFFFfffFf15e1b7E3dF971DD813Bc394deB899aBf);
	IERC20 vGMLR = IERC20(0xFfFfFFff99dABE1a8De0EA22bAa6FD48fdE96F6c);
	IERC20 vASTR = IERC20(0xFffFffff55C732C47639231a4C4373245763d26E);
	IERC20 vFIL = IERC20(0xFffffFffCd0aD0EA6576B7b285295c85E94cf4c1);

	IERC20 xcDOT = IERC20(0xFfFFfFff1FcaCBd218EDc0EbA20Fc2308C778080);
	IERC20 GMLR = IERC20(0x0000000000000000000000000000000000000802);
	IERC20 ASTR = IERC20(0xFfFFFfffA893AD19e540E172C10d78D4d479B5Cf);
	IERC20 FIL = IERC20(0xfFFfFFFF6C57e17D210DF507c82807149fFd70B2);

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		poolFactory = new MoonbeamLaunchpoolFactory();
	}

	function testCreateSinglePool() public {
		// Arrange
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(vDOT);

		address[] memory acceptedNativeAssets = new address[](1);
		acceptedNativeAssets[0] = address(xcDOT);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);

		// Assert: Check if the pool count increased
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 1, "Pool count is not 1");
		assertTrue(poolIds.length == 1, "Pool id length is not 1");
	}

	function testCreateMultiplePools() public {
		// Arrange
		address[] memory acceptedVAssets = new address[](4);
		acceptedVAssets[0] = address(vDOT);
		acceptedVAssets[1] = address(vGMLR);
		acceptedVAssets[2] = address(vASTR);
		acceptedVAssets[3] = address(vFIL);

		address[] memory acceptedNativeAssets = new address[](4);
		acceptedNativeAssets[0] = address(xcDOT);
		acceptedNativeAssets[1] = address(GMLR);
		acceptedNativeAssets[2] = address(ASTR);
		acceptedNativeAssets[3] = address(FIL);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);

		// Assert: Check if the pool count increased
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 4, "Pool count is not 4");
		assertTrue(poolIds.length == 4, "Pool id length is not 4");
	}

	function testCreateSinglePoolRepeatedly() public {
		// Arrange
		// Pool 1
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(vDOT);

		address[] memory acceptedNativeAssets = new address[](1);
		acceptedNativeAssets[0] = address(xcDOT);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Pool 2
		address[] memory acceptedVAssets1 = new address[](1);
		acceptedVAssets1[0] = address(vASTR);

		address[] memory acceptedNativeAssets1 = new address[](1);
		acceptedNativeAssets1[0] = address(ASTR);

		uint128[] memory changeBlocks1 = new uint128[](2);

		changeBlocks1[0] = 1115;
		changeBlocks1[1] = 3105;

		uint256[] memory emissionRate1 = new uint256[](2);
		emissionRate1[0] = 7;
		emissionRate1[1] = 12;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);

		uint256[] memory poolIds1 = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets1,
			acceptedNativeAssets1,
			1000,
			5000,
			20000,
			changeBlocks1,
			emissionRate1
		);

		// Assert: Check if the pool count increased
		uint256 currentPoolId = poolFactory.getPoolCount();
		assertTrue(currentPoolId == 2, "Pool count is not 2");

		assertTrue(poolIds.length == 1, "Pool id length is not 1");
		assertTrue(poolIds1.length == 1, "Pool id length is not 1");
	}

	function testFailWhenUnacceptedVAssetsAreProvided() public {
		// Arrange: Set up the pool factory and project token
		address[] memory acceptedVAssets = new address[](2);
		acceptedVAssets[0] = address(vDOT);
		acceptedVAssets[1] = address(0x0000002);

		address[] memory acceptedNativeAssets = new address[](2);
		acceptedNativeAssets[0] = address(xcDOT);
		acceptedNativeAssets[1] = address(0x0000002);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);
	}

	function testFailWhenInvalidBlockRangeIsProvided() public {
		// Arrange: Set up the pool factory and project token
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(vDOT);

		address[] memory acceptedNativeAssets = new address[](1);
		acceptedNativeAssets[0] = address(xcDOT);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act: Call createPool function
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			5000,
			1000,
			20000,
			changeBlocks,
			emissionRate
		);
	}

	function testRevertWhenInvalidEmissionRateIsProvided() public {
		// Arrange: Set up the pool factory and project token
		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(vDOT);

		address[] memory acceptedNativeAssets = new address[](1);
		acceptedNativeAssets[0] = address(xcDOT);

		uint128[] memory changeBlock = new uint128[](1);
		changeBlock[0] = 1110;

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](1);
		emissionRate[0] = 10;

		uint256[] memory emissionRates = new uint256[](2);
		emissionRates[0] = 5;
		emissionRates[1] = 10;

		// Act: Call createPool function
		vm.expectRevert(MoonbeamLaunchpoolFactory.InvalidArrayLengths.selector);
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);

		vm.expectRevert(MoonbeamLaunchpoolFactory.InvalidArrayLengths.selector);
		uint256[] memory poolIds1 = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlock,
			emissionRates
		);
	}

	function testAddAcceptedVAsset() public {
		// Arrange
		IERC20 vCAFE = IERC20(0xCAfEcAfeCAfECaFeCaFecaFecaFECafECafeCaFe);
		IERC20 CAFE = IERC20(0xb1542dEfE423c8372a90E05086587C569809cafe);

		// Act: Add a new vAsset
		poolFactory.addAcceptedVAsset(address(vCAFE), address(CAFE));

		// Assert: Check if the vAsset is added
		assertTrue(
			poolFactory.vAssetToAsset(address(vCAFE)) == address(CAFE),
			"vCAFE is not added"
		);
	}

	function testRemoveAcceptedVAsset() public {
		// Act
		poolFactory.removeAcceptedVAsset(address(vDOT));

		// Assert
		assertEq(
			poolFactory.vAssetToAsset(address(vDOT)) == address(0),
			true,
			"vDOT is not removed"
		);
	}

	function testFailWhenUsingRemovedVAsset() public {
		// Arrange
		poolFactory.removeAcceptedVAsset(address(vDOT));

		address[] memory acceptedVAssets = new address[](1);
		acceptedVAssets[0] = address(vDOT);

		address[] memory acceptedNativeAssets = new address[](1);
		acceptedNativeAssets[0] = address(xcDOT);

		uint128[] memory changeBlocks = new uint128[](2);
		changeBlocks[0] = 1110;
		changeBlocks[1] = 3000;

		uint256[] memory emissionRate = new uint256[](2);
		emissionRate[0] = 5;
		emissionRate[1] = 10;

		// Act
		uint256[] memory poolIds = poolFactory.createPools(
			address(projectToken),
			acceptedVAssets,
			acceptedNativeAssets,
			1000,
			5000,
			20000,
			changeBlocks,
			emissionRate
		);
	}
}
