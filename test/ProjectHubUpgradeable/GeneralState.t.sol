// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProjectHubUpgradeable } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { DeployProjectHubModifiedSender } from "../testutils/DeployProjectHubModifiedSender.sol";
import { ProjectHubUpgradeable } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";

contract GeneralStateTest is Test {
	MockERC20 public projectToken;
	MockERC20 public vAsset;
	MockERC20 vDOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 vGMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 vASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 vFIL = new MockERC20("Voucher FIL", "vFIL");
	DeployProjectHubModifiedSender public hubDeployScript;
	address[] vAssets;
	uint64 public projectId;
	address public projectHubProxy;

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
		projectId = 1; // First project ID
	}

	function test_initialized_acceptedVAssets() public {
		for (uint256 i; i < vAssets.length; ++i) {
			bytes memory callPayload = abi.encodeWithSignature(
				"acceptedVAssets(address)",
				(vAssets[i])
			);

			(bool success, bytes memory returnData) = projectHubProxy.call(
				callPayload
			);
			assert(success == true);

			bool isAccepted = abi.decode(returnData, (bool));
			assertEq(
				isAccepted,
				true,
				string.concat(
					"vAsset ",
					vm.toString(vAssets[i]),
					" should be accepted if project hub had been initialized"
				)
			);
		}
	}

	function test_initialized_owner() public {
		bytes memory callPayload = abi.encodeWithSignature("owner()");
		(bool success, bytes memory returnData) = projectHubProxy.call(
			callPayload
		);
		assert(success == true);
		address projectHubOwner = abi.decode(returnData, (address));
		assertEq(
			projectHubOwner,
			address(this),
			"Owner should be the deployer of the project hub"
		);
	}

	function test_initialized_nextPoolId() public {
		bytes memory callPayload = abi.encodeWithSignature("nextPoolId()");
		(bool success, bytes memory returnData) = projectHubProxy.call(
			callPayload
		);
		assert(success == true);
		uint64 nextPoolId = abi.decode(returnData, (uint64));
		assertEq(nextPoolId, 1, "Initial value of nextPoolId should be 1");
	}

	function test_intialized_nextProjectId() public {
		bytes memory callPayload = abi.encodeWithSignature("nextProjectId()");
		(bool success, bytes memory returnData) = projectHubProxy.call(
			callPayload
		);
		assert(success == true);
		uint64 nextProjectId = abi.decode(returnData, (uint64));
		assertEq(
			nextProjectId,
			1,
			"Initial value of nextProjectId should be 1"
		);
	}
}
