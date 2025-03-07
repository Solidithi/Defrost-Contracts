// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProjectHubUpgradeable, LaunchpoolLibrary, ProjectLibrary } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { DeployProjectHubProxyCustomSender } from "../testutils/DeployProjectHubProxyCustomSender.sol";
import { IProjectHub } from "@src/interfaces/IProjectHub.sol";
import { ILaunchpool } from "@src/interfaces/ILaunchpool.sol";

contract CreateLaunchpoolTest is Test {
	MockERC20 public projectToken;
	MockERC20 vDOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 vGMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 vASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 vFIL = new MockERC20("Voucher FIL", "vFIL");
	DeployProjectHubProxyCustomSender public hubDeployScript;
	address[] vAssets;
	address public projectHubProxy;
	uint256 public constant BLOCK_TIME = 6;

	constructor() {
		vAssets.push(address(vDOT));
		vAssets.push(address(vGMLR));
		vAssets.push(address(vASTR));
		vAssets.push(address(vFIL));
		hubDeployScript = new DeployProjectHubProxyCustomSender(
			vAssets,
			address(this)
		);
	}

	function setUp() public {
		projectToken = new MockERC20("PROJECT", "PRO");

		// Deploy and initialize ProjectHub
		projectHubProxy = hubDeployScript.deployProjectHubProxy();
	}

	function test_next_project_id() public {
		// Arrange:
		// 1. Get initial value of nextProjectId
		uint nextProjectIdBefore = IProjectHub(projectHubProxy).nextProjectId();

		// Act:
		// 1. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint nextProjectIdAfter = IProjectHub(projectHubProxy).nextProjectId();

		// Assert:
		assertEq(
			nextProjectIdBefore,
			1,
			"Initial value of nextProjectId should be 1"
		);
		assertEq(nextProjectIdAfter, nextProjectIdBefore + 1);
	}

	function test_create_single_launchpool() public {
		// Arrange:
		// 1. Get initial value of nextPoolId
		uint64 nextPoolIdBefore = IProjectHub(projectHubProxy).nextPoolId();

		// 2. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint64 projectId = IProjectHub(projectHubProxy).nextProjectId() - 1;
		uint128[] memory changeBlocks = new uint128[](2);
		uint256[] memory emissionRateChanges = new uint256[](2);
		uint128 startBlock = uint128(block.number + 1);
		uint128 endBlock = uint128(block.number + 100);

		// 3. Prepare a set of params for launchpool creation
		LaunchpoolLibrary.LaunchpoolCreationParams
			memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
				projectId: uint64(projectId),
				projectToken: address(projectToken),
				vAsset: address(vDOT),
				startBlock: startBlock,
				endBlock: endBlock,
				maxVTokensPerStaker: 1000 * 1e18,
				changeBlocks: changeBlocks,
				emissionRateChanges: emissionRateChanges,
				isListed: true
			});

		// Act:
		// 1. Create a launchpool for the project
		uint64 poolId = ProjectHubUpgradeable(projectHubProxy).createLaunchpool(
			params
		);
		uint64 nextPoolIdAfter = IProjectHub(projectHubProxy).nextPoolId();

		// Assert:
		// 1. Assert nextPoolId increases
		assertEq(
			nextPoolIdBefore,
			1,
			"Initial value of nextPoolId should be 1"
		);
		assertEq(nextPoolIdAfter, nextPoolIdBefore + 1, "what the fuck");
		// 2. Assert pool info
		(
			uint256 _poolId,
			,
			address _poolAddress,
			uint64 _projectId,

		) = ProjectHubUpgradeable(projectHubProxy).pools(nextPoolIdBefore);
		assertEq(_projectId, projectId, "Wrong project Id");
		assertEq(_poolId, poolId, "Wrong pool Id");
		assertEq(ILaunchpool(_poolAddress).owner(), address(this)); // deep assertion to be sure

		// 3. Assert PoolCreated event emission
		// Setup expected event
		vm.expectEmit(true, true, true, false, projectHubProxy);
		emit LaunchpoolLibrary.PoolCreated(
			projectId,
			LaunchpoolLibrary.PoolType.LAUNCHPOOL,
			poolId + 1,
			address(projectToken),
			address(vDOT),
			address(0), // We dont' know this address yet, will match anything
			startBlock,
			endBlock
		);

		// Call createLaunchpool again to trigger event emission
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);
	}

	function test_create_multiple_launchpools() public {
		// Arrange:
		// 1. Get initial value of nextPoolId
		uint64 nextPoolIdBefore = IProjectHub(projectHubProxy).nextPoolId();

		// 2. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint64 projectId = IProjectHub(projectHubProxy).nextProjectId() - 1;

		// 3. Prepare a set of params for launchpool creation
		uint128 startBlock = uint128(block.number + 1);
		uint128 poolDurationBlocks = uint128(30 days / BLOCK_TIME);
		uint128 endBlock = uint128(startBlock + poolDurationBlocks);
		uint128[] memory changeBlocks = new uint128[](3);
		changeBlocks[0] = startBlock + uint128((poolDurationBlocks * 1) / 3);
		changeBlocks[1] = startBlock + poolDurationBlocks / 2;
		changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4;
		uint256[] memory emissionRateChanges = new uint256[](3);
		emissionRateChanges[0] = 1000;
		emissionRateChanges[1] = 500;
		emissionRateChanges[2] = 200;

		uint256 poolCount = 86;
		bytes[] memory callPayloadBatch = new bytes[](poolCount);
		for (uint256 i; i < poolCount; ++i) {
			LaunchpoolLibrary.LaunchpoolCreationParams
				memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
					projectId: uint64(projectId),
					projectToken: address(projectToken),
					vAsset: address(vDOT),
					startBlock: startBlock,
					endBlock: endBlock,
					maxVTokensPerStaker: 8686 * (10 ** vDOT.decimals()),
					changeBlocks: changeBlocks,
					emissionRateChanges: emissionRateChanges,
					isListed: i % 2 == 0 ? true : false
				});
			bytes memory callPayload = abi.encodeWithSelector(
				IProjectHub(projectHubProxy).createLaunchpool.selector,
				params
			);
			callPayloadBatch[i] = callPayload;
		}
		// Prepare selfMultiCall payload
		bytes memory selfMulticallPayload = abi.encodeWithSignature(
			"selfMultiCall(bytes[])",
			callPayloadBatch
		);

		// Act:
		// 1. Before the batch call, start recording logs
		vm.recordLogs();
		// 2. Create multiple pools (execute batch transaction)
		(bool success, bytes memory allReturnData) = address(projectHubProxy)
			.call(selfMulticallPayload);
		assertEq(
			success,
			true,
			"Batch transaction to create multiple pools failed"
		);
		// 3. Get all recorded logs
		Vm.Log[] memory logs = vm.getRecordedLogs();

		// Assert:
		// Count PoolCreated events
		bytes32 poolCreatedSignature = keccak256(
			"PoolCreated(uint64,uint8,uint64,address,address,address,uint128,uint128)"
		);

		// Debug information
		console.log("Total logs emitted:", logs.length);

		uint256 poolCreatedEventCount = 0;
		for (uint256 i = 0; i < logs.length; i++) {
			if (logs[i].topics[0] == poolCreatedSignature) {
				++poolCreatedEventCount;
				// 1. Extract indexed parameters from topics
				uint64 _projectId = uint64(uint256(logs[i].topics[1]));
				uint8 _poolType = uint8(uint256(logs[i].topics[2]));
				address _vAsset = address(uint160(uint256(logs[i].topics[3])));

				// 2. Decode non-indexed parameters from data
				(
					uint64 _poolId,
					address _projectToken,
					address _poolAddress,
					uint128 _startBlock,
					uint128 _endBlock
				) = abi.decode(
						logs[i].data,
						(uint64, address, address, uint128, uint128)
					);
				assertEq(_projectId, projectId, "projectId mismatch");
				assertEq(_poolType, 0, "pool type mismatch");
				assertEq(
					_projectToken,
					address(projectToken),
					"projectToken mismatch"
				);
				assertEq(_vAsset, address(vDOT), "vAsset mismatch");
				assertEq(_startBlock, startBlock, "startBlock mismatch");
				assertEq(_endBlock, endBlock, "endBlock mismatch");
				assertEq(
					_poolAddress,
					IProjectHub(projectHubProxy).pools(_poolId).poolAddress,
					"poolAddress mismatch"
				);
			}
		}
		assertEq(
			poolCreatedEventCount,
			poolCount,
			"Wrong number of PoolCreated events emitted"
		);

		bytes[] memory returnBytesArray = abi.decode(allReturnData, (bytes[]));
		assertEq(
			returnBytesArray.length,
			poolCount,
			"Wrong number of pools created"
		);
		uint64[] memory allPoolIds = new uint64[](poolCount);
		for (uint256 i; i < poolCount; ++i) {
			uint64 poolId = abi.decode(returnBytesArray[i], (uint64));
			allPoolIds[i] = poolId;
		}

		assertEq(allPoolIds.length, poolCount, "Wrong number of pools created");
		assertEq(
			allPoolIds[0],
			allPoolIds[poolCount - 1] - poolCount + 1,
			"Pool created rapidly should have consecutive Ids"
		);
		assertEq(
			allPoolIds[0],
			nextPoolIdBefore,
			"Initial value of nextPoolId should be the first pool Id"
		);
		uint64 nextPoolIdAfter = IProjectHub(projectHubProxy).nextPoolId();
		assertEq(
			nextPoolIdAfter,
			nextPoolIdBefore + poolCount,
			"nextPoolId after creating multiple pools doesn't correctly reflect the amount of pool created"
		);
	}

	// function testCreatePoolFailsWithoutProject() public {
	// 	// Arrange
	// 	address[] memory acceptedVAssets = new address[](1);
	// 	acceptedVAssets[0] = address(vAsset);

	// 	uint128[] memory changeBlocks = new uint128[](2);
	// 	changeBlocks[0] = 1110;
	// 	changeBlocks[1] = 3000;

	// 	uint256[] memory emissionRate = new uint256[](2);
	// 	emissionRate[0] = 5;
	// 	emissionRate[1] = 10;

	// 	// Act & Assert
	// 	vm.expectRevert(ProjectHubUpgradeable.ProjectNotFound.selector);
	// 	projectHubProxy.createLaunchpools(
	// 		999, // Non-existent project ID
	// 		address(projectToken),
	// 		acceptedVAssets,
	// 		1000,
	// 		5000,
	// 		20000,
	// 		changeBlocks,
	// 		emissionRate
	// 	);
	// }

	// function testFailCreatePoolWithInvalidVAsset() public {
	// 	// Arrange
	// 	address[] memory acceptedVAssets = new address[](1);
	// 	acceptedVAssets[0] = address(vAsset); // vAsset not added to accepted list

	// 	uint128[] memory changeBlocks = new uint128[](2);
	// 	changeBlocks[0] = 1110;
	// 	changeBlocks[1] = 3000;

	// 	uint256[] memory emissionRate = new uint256[](2);
	// 	emissionRate[0] = 5;
	// 	emissionRate[1] = 10;

	// 	// Act & Assert - Should revert with NotAcceptedVAsset
	// 	projectHubProxy.createLaunchpools(
	// 		projectId,
	// 		address(projectToken),
	// 		acceptedVAssets,
	// 		1000,
	// 		5000,
	// 		20000,
	// 		changeBlocks,
	// 		emissionRate
	// 	);
	// }
}
