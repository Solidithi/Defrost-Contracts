// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProjectHubUpgradeable, LaunchpoolLibrary, ProjectLibrary, PoolTypeLib } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { DeployProjectHubProxyCustomSender } from "../testutils/DeployProjectHubProxyCustomSender.sol";
import { IProjectHub } from "@src/interfaces/IProjectHub.sol";
import { ILaunchpool } from "@src/interfaces/ILaunchpool.sol";
import { DeployMockXCMOracle } from "../testutils/DeployMockXCMOracle.sol";

contract CreateLaunchpoolTest is Test {
	MockERC20 public projectToken = new MockERC20("PROJECT", "PRO");
	uint256 projectTokenAmount = 1e7 * 10 ** projectToken.decimals();

	MockERC20 vDOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 vGMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 vASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 vFIL = new MockERC20("Voucher FIL", "vFIL");

	MockERC20 DOT = new MockERC20("Voucher DOT", "vDOT");
	MockERC20 GMLR = new MockERC20("Voucher GMLR", "vGMLR");
	MockERC20 ASTR = new MockERC20("Voucher ASTR", "vASTR");
	MockERC20 FIL = new MockERC20("Voucher FIL", "vFIL");

	MockXCMOracle public mockXCMOracle = new MockXCMOracle(12000, 10, 80000, 6);

	DeployProjectHubProxyCustomSender public hubDeployScript;
	DeployMockXCMOracle mockXCMOracleDeployer = new DeployMockXCMOracle();
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
		// Deploy and initialize ProjectHub
		projectHubProxy = hubDeployScript.deployProjectHubProxy();

		// Put MockXCMOracle at the hard-coded address of real on-chain XCMOracle
		mockXCMOracleDeployer.deploy(12000, 10, 80000, 6);
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
		changeBlocks[0] = startBlock;
		changeBlocks[1] = startBlock + 1;
		emissionRateChanges[0] = 1000 * 10 ** projectToken.decimals();
		emissionRateChanges[0] = 500 * 10 ** projectToken.decimals();

		// 3. Prepare a set of params for launchpool creation
		LaunchpoolLibrary.LaunchpoolCreationParams
			memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
				projectId: uint64(projectId),
				projectTokenAmount: projectTokenAmount,
				projectToken: address(projectToken),
				vAsset: address(vDOT),
				startBlock: startBlock,
				endBlock: endBlock,
				maxVTokensPerStaker: 1000 * 1e18,
				changeBlocks: changeBlocks,
				emissionRateChanges: emissionRateChanges
			});

		// Act:
		// 1. Create a launchpool for the project
		projectToken.freeMint(projectTokenAmount);
		projectToken.approve(projectHubProxy, projectTokenAmount);
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
			uint64 _projectId
		) = ProjectHubUpgradeable(projectHubProxy).pools(nextPoolIdBefore);
		assertEq(_projectId, projectId, "Wrong project Id");
		assertEq(_poolId, poolId, "Wrong pool Id");
		assertEq(ILaunchpool(_poolAddress).owner(), address(this));

		// 3. Assert PoolCreated event emission
		// Setup expected event
		projectToken.freeMint(projectTokenAmount);
		projectToken.approve(projectHubProxy, projectTokenAmount);
		vm.expectEmit(true, true, true, false, projectHubProxy);
		emit LaunchpoolLibrary.LaunchpoolCreated(
			projectId,
			PoolTypeLib.PoolType.LAUNCHPOOL,
			poolId + 1,
			address(projectToken),
			address(vDOT),
			address(DOT),
			address(0), // We dont' know this address yet, will match anything
			startBlock,
			endBlock
		);

		// Call createLaunchpool again to trigger event emission
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);

		// 4. Assert project token balance in launchpool matches with that in params
		uint256 launchpoolBalance = projectToken.balanceOf(_poolAddress);
		assertEq(
			launchpoolBalance,
			params.projectTokenAmount,
			"Project token balance in launchpool doesn't match with that in params"
		);
	}

	function test_create_multiple_launchpools() public {
		("Address of test contract is: %s", address(this));
		// Arrange:
		// 1. Get initial value of nextPoolId
		uint256 poolCount = 86;
		uint64 nextPoolIdBefore = IProjectHub(projectHubProxy).nextPoolId();

		// 2. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint64 projectId = IProjectHub(projectHubProxy).nextProjectId() - 1;

		// 3. Fund just enough project tokens for all the pools that will be created soon
		projectToken.freeMint(projectTokenAmount * poolCount);
		projectToken.approve(projectHubProxy, projectTokenAmount * poolCount);

		// 4. Prepare a set of params for launchpool creation
		uint128 startBlock = uint128(block.number + 1);
		uint128 poolDurationBlocks = uint128(30 days / BLOCK_TIME);
		uint128 endBlock = uint128(startBlock + poolDurationBlocks);
		uint128[] memory changeBlocks = new uint128[](3);
		changeBlocks[0] = startBlock;
		changeBlocks[1] = startBlock + poolDurationBlocks / 2;
		changeBlocks[2] = startBlock + (poolDurationBlocks * 3) / 4;
		uint256[] memory emissionRateChanges = new uint256[](3);
		emissionRateChanges[0] = 1000 * 10 ** projectToken.decimals();
		emissionRateChanges[1] = 500 * 10 ** projectToken.decimals();
		emissionRateChanges[2] = 200 * 10 ** projectToken.decimals();

		bytes[] memory callPayloadBatch = new bytes[](poolCount);
		for (uint256 i; i < poolCount; ++i) {
			LaunchpoolLibrary.LaunchpoolCreationParams
				memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
					projectId: uint64(projectId),
					projectTokenAmount: projectTokenAmount,
					projectToken: address(projectToken),
					vAsset: address(vDOT),
					startBlock: startBlock,
					endBlock: endBlock,
					maxVTokensPerStaker: 8686 * (10 ** vDOT.decimals()),
					changeBlocks: changeBlocks,
					emissionRateChanges: emissionRateChanges
				});
			bytes memory callPayload = abi.encodeWithSelector(
				ProjectHubUpgradeable(projectHubProxy)
					.createLaunchpool
					.selector,
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
		bytes32 sigLaunchpoolCreated = keccak256(
			"LaunchpoolCreated(uint64,uint8,uint64,address,address,address,address,uint128,uint128)"
		);

		// Debug information
		console.log("Total logs emitted:", logs.length);

		uint256 launchpoolCreatedEventCount = 0;
		for (uint256 i = 0; i < logs.length; i++) {
			if (logs[i].topics[0] == sigLaunchpoolCreated) {
				++launchpoolCreatedEventCount;
				// 1. Extract indexed parameters from topics
				uint64 _projectId = uint64(uint256(logs[i].topics[1]));
				uint8 _poolType = uint8(uint256(logs[i].topics[2]));
				address _vAsset = address(uint160(uint256(logs[i].topics[3])));

				// 2. Decode non-indexed parameters from data
				(
					uint64 _poolId,
					address _projectToken,
					address _nativeAsset,
					address _poolAddress,
					uint128 _startBlock,
					uint128 _endBlock
				) = abi.decode(
						logs[i].data,
						(uint64, address, address, address, uint128, uint128)
					);
				assertEq(_projectId, projectId, "projectId mismatch");
				assertEq(_poolType, 0, "pool type mismatch");
				assertEq(
					_projectToken,
					address(projectToken),
					"projectToken mismatch"
				);
				assertEq(_nativeAsset, address(DOT), "nativeAsset mismatch");
				assertEq(_vAsset, address(vDOT), "vAsset mismatch");
				assertEq(_startBlock, startBlock, "startBlock mismatch");
				assertEq(_endBlock, endBlock, "endBlock mismatch");
				assertEq(
					_poolAddress,
					IProjectHub(projectHubProxy).pools(_poolId).poolAddress,
					"poolAddress mismatch"
				);
				uint256 launchpoolBalance = projectToken.balanceOf(
					_poolAddress
				);
				assertEq(
					launchpoolBalance,
					projectTokenAmount,
					"Project token balance in launchpool doesn't match with that in params"
				);
			}
		}
		assertEq(
			launchpoolCreatedEventCount,
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

	function test_revert_create_launchpool_not_project_owner() public {
		// Arrange:
		// 1. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint64 projectId = IProjectHub(projectHubProxy).nextProjectId() - 1;
		uint128[] memory changeBlocks = new uint128[](2);
		uint256[] memory emissionRateChanges = new uint256[](2);
		uint128 startBlock = uint128(block.number + 1);
		uint128 endBlock = uint128(block.number + 100);

		// 2. Prepare a set of params for launchpool creation
		LaunchpoolLibrary.LaunchpoolCreationParams
			memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
				projectId: uint64(projectId),
				projectTokenAmount: projectTokenAmount,
				projectToken: address(projectToken),
				vAsset: address(vDOT),
				startBlock: startBlock,
				endBlock: endBlock,
				maxVTokensPerStaker: 1000 * 1e18,
				changeBlocks: changeBlocks,
				emissionRateChanges: emissionRateChanges
			});

		// Act:
		// 1. Expect revert with custom error NotProjectOwner()
		vm.expectRevert(
			abi.encodeWithSelector(ProjectLibrary.NotProjectOwner.selector)
		);

		// 2. Impersonate a non-owner account, create a launchpool and see revert
		vm.prank(address(1));
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);
	}

	function test_revert_create_launchpool_not_registered_vAsset() public {
		// Arrange:
		// 1. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint64 projectId = IProjectHub(projectHubProxy).nextProjectId() - 1;

		// 2. Create a shitcoin for demonstration
		MockERC20 shitcoin = new MockERC20("Shit coin", "SHIT");

		// 3. Prepare a set of params for launchpool creation (insert shitcoin into params)
		uint128[] memory changeBlocks = new uint128[](2);
		uint256[] memory emissionRateChanges = new uint256[](2);
		uint128 startBlock = uint128(block.number + 1);
		uint128 endBlock = uint128(block.number + 100);
		LaunchpoolLibrary.LaunchpoolCreationParams
			memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
				projectId: uint64(projectId),
				projectTokenAmount: projectTokenAmount,
				projectToken: address(projectToken),
				vAsset: address(shitcoin), // put shitcoin here
				startBlock: startBlock,
				endBlock: endBlock,
				maxVTokensPerStaker: 1000 * 1e18,
				changeBlocks: changeBlocks,
				emissionRateChanges: emissionRateChanges
			});

		// Act:
		// 1.expect revert with custom error NotAcceptedVAsset()
		vm.expectRevert(ProjectHubUpgradeable.NotAcceptedVAsset.selector);
		//2. Create a launchpool with a non-accepted vAsset (shitcoin)
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);
	}

	function test_revert_create_launchpool_project_not_found() public {
		// Arrange:
		// 1. Retrieve a non-existent project ID
		uint64 projectId = ProjectHubUpgradeable(projectHubProxy)
			.nextProjectId();

		// 2. Prepare a set of params for launchpool creation
		uint128 startBlock = uint128(block.number + 1);
		uint128 endBlock = uint128(block.number + 100);
		uint128[] memory changeBlocks = new uint128[](2);
		uint256[] memory emissionRateChanges = new uint256[](2);
		LaunchpoolLibrary.LaunchpoolCreationParams
			memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
				projectId: uint64(projectId),
				projectTokenAmount: projectTokenAmount,
				projectToken: address(projectToken),
				vAsset: address(vDOT),
				startBlock: startBlock,
				endBlock: endBlock,
				maxVTokensPerStaker: 1000 * 1e18,
				changeBlocks: changeBlocks,
				emissionRateChanges: emissionRateChanges
			});
		// 3. Expect revert with custom error ProjectNotFound()
		vm.expectRevert(ProjectLibrary.ProjectNotFound.selector);

		// Act & Assert:
		// 1. Call createLaunchpool with non-existent project ID and wait for revert
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);
	}

	function test_revert_create_launchpool_not_enough_project_token_allowance()
		public
	{
		// Arrange:
		// 1. Create a project
		IProjectHub(projectHubProxy).createProject();
		uint64 projectId = IProjectHub(projectHubProxy).nextProjectId() - 1;

		// 2. Prepare a set of params for launchpool creation
		uint128 startBlock = uint128(block.number + 1);
		uint128 endBlock = uint128(block.number + 100);
		uint128[] memory changeBlocks = new uint128[](2);
		uint256[] memory emissionRateChanges = new uint256[](2);
		changeBlocks[0] = startBlock;
		changeBlocks[1] = startBlock + 1;
		emissionRateChanges[0] = 1000 * 10 ** projectToken.decimals();
		emissionRateChanges[1] = 500 * 10 ** projectToken.decimals();

		LaunchpoolLibrary.LaunchpoolCreationParams
			memory params = LaunchpoolLibrary.LaunchpoolCreationParams({
				projectId: uint64(projectId),
				projectTokenAmount: projectTokenAmount,
				projectToken: address(projectToken),
				vAsset: address(vDOT),
				startBlock: startBlock,
				endBlock: endBlock,
				maxVTokensPerStaker: 1000 * 1e18,
				changeBlocks: changeBlocks,
				emissionRateChanges: emissionRateChanges
			});

		// 3. Set project token allowance to 0
		projectToken.approve(projectHubProxy, 0);

		// Act:
		// 1. Call createLaunchpool and expect revert
		vm.expectRevert(
			abi.encodeWithSignature(
				"ERC20InsufficientAllowance(address,uint256,uint256)",
				projectHubProxy,
				0,
				projectTokenAmount
			)
		);
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);

		// 2. Set project token allowance to be equal to project token amount
		projectToken.freeMint(projectTokenAmount); // mint just to make sure
		projectToken.approve(projectHubProxy, projectTokenAmount);

		// 3 Use tokens so that the balance drop below allowance
		uint256 initialBalance = projectToken.balanceOf(address(this));
		projectToken.transfer(
			address(1),
			initialBalance - projectTokenAmount + 1
		);
		uint256 finalBalance = projectToken.balanceOf(address(this));
		console.log("Balance:", finalBalance);
		console.log("Required:", projectTokenAmount);
		require(
			finalBalance < projectTokenAmount,
			"Balance should be insufficient"
		);

		// 4. Call createLaunchpool and expect revert once again
		vm.expectRevert(
			abi.encodeWithSignature(
				"ERC20InsufficientBalance(address,uint256,uint256)",
				address(this),
				finalBalance,
				projectTokenAmount
			)
		);
		ProjectHubUpgradeable(projectHubProxy).createLaunchpool(params);
	}
}
