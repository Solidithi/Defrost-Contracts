// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { ProjectHubUpgradeable, PoolTypeLib } from "@src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { DeployProjectHubProxyCustomSender } from "../testutils/DeployProjectHubProxyCustomSender.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ILaunchpool } from "@src/interfaces/ILaunchpool.sol";

contract GeneralSetters is Test {
	MockERC20 public projectToken;
	MockERC20 public vAsset;

	MockERC20 vDOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 vGMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 vASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 vFIL = new MockERC20("Voucher FIL", "vFIL");

	MockERC20 DOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 GMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 ASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 FIL = new MockERC20("Voucher FIL", "vFIL");

	DeployProjectHubProxyCustomSender public hubDeployScript;
	address[] vAssets;
	address[] nativeAssets;
	address public projectHubProxy;
	uint256 public constant BLOCK_TIME = 6;

	constructor() {
		vAssets.push(address(vDOT));
		vAssets.push(address(vGMLR));
		vAssets.push(address(vASTR));
		vAssets.push(address(vFIL));
		nativeAssets.push(address(DOT));
		nativeAssets.push(address(GMLR));
		nativeAssets.push(address(ASTR));
		nativeAssets.push(address(FIL));
		hubDeployScript = new DeployProjectHubProxyCustomSender(
			vAssets,
			nativeAssets,
			address(this)
		);
	}

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");

		// Deploy and initialize ProjectHub
		projectHubProxy = hubDeployScript.deployProjectHubProxy();
	}

	function test_set_native_asset_for_vAsset() public {
		// Arrange:
		// Check owner permission beforehand
		assert(ProjectHubUpgradeable(projectHubProxy).owner() == address(this));
		// Deploy new asset pair
		MockERC20 newVAsset = new MockERC20("New Voucher Token", "vNew");
		MockERC20 newNativeAsset = new MockERC20("New Native", "New");

		// Act:
		// Verify initial state is not set
		assertEq(
			ProjectHubUpgradeable(projectHubProxy).vAssetToNativeAsset(
				address(newVAsset)
			),
			address(0)
		);

		// Set vAsset2 as accepted vAsset
		ProjectHubUpgradeable(projectHubProxy).setNativeAssetForVAsset(
			address(newVAsset),
			address(newNativeAsset)
		);

		// Assert:
		address nativeAssetAddress = ProjectHubUpgradeable(projectHubProxy)
			.vAssetToNativeAsset(address(newVAsset));
		assertEq(
			nativeAssetAddress,
			address(newNativeAsset),
			"Native asset for vAsset should be set"
		);
	}

	function test_revert_set_accepted_vAsset_not_owner() public {
		// Arrange:
		// Check owner permission beforehand
		assert(ProjectHubUpgradeable(projectHubProxy).owner() == address(this));
		// Deploy new asset pair
		MockERC20 newVAsset = new MockERC20("New Voucher Token", "vNew");
		MockERC20 newNativeAsset = new MockERC20("New Native", "New");

		// Act & Assert:
		// Set vAsset2 as accepted vAsset
		address alice = vm.addr(0x868);
		vm.expectRevert(
			abi.encodeWithSelector(
				OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
				alice
			)
		);
		vm.prank(alice);
		ProjectHubUpgradeable(projectHubProxy).setNativeAssetForVAsset(
			address(newVAsset),
			address(newNativeAsset)
		);
	}

	function test_set_multiple_accepted_vAssets() public {
		// Arrange & Act:
		// Check owner permission beforehand
		assert(ProjectHubUpgradeable(projectHubProxy).owner() == address(this));
		// Deploy multiple mock vAssets and set them as accepted vAssets in projectHub contract
		uint256 vAssetsCount = 86;
		MockERC20[] memory additionalVAssets = new MockERC20[](vAssetsCount);
		MockERC20[] memory additionalNativeAssets = new MockERC20[](
			vAssetsCount
		);
		for (uint256 i; i < vAssetsCount; ++i) {
			additionalVAssets[i] = new MockERC20(
				string(abi.encodePacked("Voucher Imaginary ", i)),
				string(abi.encodePacked("vImaginary", i))
			);
			additionalNativeAssets[i] = new MockERC20(
				string(abi.encodePacked("Native Asset ", i)),
				string(abi.encodePacked("Native ", i))
			);
			ProjectHubUpgradeable(projectHubProxy).setNativeAssetForVAsset(
				address(additionalVAssets[i]),
				address(additionalNativeAssets[i])
			);
		}

		// Assert:
		for (uint256 i; i < vAssetsCount; ++i) {
			address nativeAssetAddress = ProjectHubUpgradeable(projectHubProxy)
				.vAssetToNativeAsset(address(additionalVAssets[i]));
			assertEq(
				nativeAssetAddress,
				address(additionalNativeAssets[i]),
				string(abi.encodePacked("vAsset ", i, "should be accepted"))
			);
		}
	}
}
