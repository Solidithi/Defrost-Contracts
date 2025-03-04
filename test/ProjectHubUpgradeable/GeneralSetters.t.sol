// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { ProjectHubUpgradeable } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { DeployProjectHubModifiedSender } from "../testutils/DeployProjectHubModifiedSender.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ILaunchpool } from "@src/interfaces/ILaunchpool.sol";

contract GeneralSetters is Test {
	MockERC20 public projectToken;
	MockERC20 public vAsset;
	MockERC20 vDOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 vGMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 vASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 vFIL = new MockERC20("Voucher FIL", "vFIL");
	DeployProjectHubModifiedSender public hubDeployScript;
	address[] vAssets;
	address public projectHubProxy;
	uint256 public constant BLOCK_TIME = 6;

	constructor() {
		vAssets.push(address(vDOT));
		vAssets.push(address(vGMLR));
		vAssets.push(address(vASTR));
		vAssets.push(address(vFIL));
		hubDeployScript = new DeployProjectHubModifiedSender(
			vAssets,
			address(this)
		);
	}

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");
		vAsset = new MockERC20("Voucher Imaginary", "vImaginary");

		// Deploy and initialize ProjectHub
		projectHubProxy = hubDeployScript.deployProjectHubProxy();
	}

	function test_set_accepted_vAsset() public {
		// Arrange:
		// Check owner permission beforehand
		assert(ProjectHubUpgradeable(projectHubProxy).owner() == address(this));
		// Deploy another mock vAsset
		MockERC20 vAsset2 = new MockERC20("Voucher Imaginary 2", "vImaginary2");

		// Act:
		// Set vAsset2 as accepted vAsset
		// Verify initial state is false
		assertEq(
			ProjectHubUpgradeable(projectHubProxy).acceptedVAssets(
				address(vAsset2)
			),
			false
		);

		ProjectHubUpgradeable(projectHubProxy).setAcceptedVAsset(
			address(vAsset2),
			true
		);

		// Assert:
		bool isAccepted = ProjectHubUpgradeable(projectHubProxy)
			.acceptedVAssets(address(vAsset2));
		assertEq(isAccepted, true, "vAsset2 should be accepted");
	}

	function test_revert_set_accepted_vAsset_not_owner() public {
		// Arrange:
		// Check owner permission beforehand
		assert(ProjectHubUpgradeable(projectHubProxy).owner() == address(this));
		// Deploy another mock vAsset
		MockERC20 vAsset2 = new MockERC20("Voucher Imaginary 2", "vImaginary2");

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
		ProjectHubUpgradeable(projectHubProxy).setAcceptedVAsset(
			address(vAsset2),
			true
		);
	}

	function test_set_multiple_accepted_vAssets() public {
		// Arrange & Act:
		// Check owner permission beforehand
		assert(ProjectHubUpgradeable(projectHubProxy).owner() == address(this));
		// Deploy multiple mock vAssets and set them as accepted vAssets in projectHub contract
		uint256 vAssetsCount = 86;
		MockERC20[] memory additionalVAssets = new MockERC20[](vAssetsCount);
		for (uint256 i; i < vAssetsCount; ++i) {
			additionalVAssets[i] = new MockERC20(
				string(abi.encodePacked("Voucher Imaginary ", i)),
				string(abi.encodePacked("vImaginary", i))
			);
			ProjectHubUpgradeable(projectHubProxy).setAcceptedVAsset(
				address(additionalVAssets[i]),
				true
			);
		}

		// Assert:
		for (uint256 i; i < vAssetsCount; ++i) {
			bool isAccepted = ProjectHubUpgradeable(projectHubProxy)
				.acceptedVAssets(address(additionalVAssets[i]));
			assertEq(
				isAccepted,
				true,
				string(abi.encodePacked("vAsset ", i, "should be accepted"))
			);
		}
	}
}
