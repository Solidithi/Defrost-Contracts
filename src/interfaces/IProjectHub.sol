// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { ProjectHubUpgradeable } from "@src/upgradeable/v1/ProjectHubUpgradeable.sol";

interface IProjectHub {
	// Type definitions
	enum PoolType {
		LAUNCHPOOL,
		LAUNCHPAD,
		VESTING,
		FARMING
	}

	struct Project {
		uint64 projectId;
		address projectOwner;
	}

	struct Pool {
		uint64 poolId;
		PoolType poolType;
		address poolAddress;
		uint64 projectId;
		bool isListed;
	}

	struct LaunchpoolCreationParams {
		uint64 projectId;
		address projectToken;
		address vAsset;
		uint128 startBlock;
		uint128 endBlock;
		uint256 maxVTokensPerStaker;
		uint128[] changeBlocks;
		uint256[] emissionRateChanges;
		bool isListed;
	}

	// Events
	event ProjectCreated(
		uint64 indexed projectId,
		address indexed projectOwner
	);
	event PoolCreated(
		uint64 indexed projectId,
		PoolType indexed poolType,
		uint64 poolId,
		address projectToken,
		address indexed vAsset,
		address poolAddress,
		uint128 startBlock,
		uint128 endBlock
	);
	event ProjectListingChanged(uint64 indexed projectId, bool isListed);

	// Functions
	function initialize(
		address _initialOwner,
		address[] calldata _initialVAssets
	) external;

	function createProject() external;

	function listPool(uint64 _poolId) external;

	function unlistProject(uint64 _poolId) external;

	function createLaunchpool(
		LaunchpoolCreationParams memory params
	) external returns (uint64);

	function setAcceptedVAsset(address _vAsset, bool _isAccepted) external;

	// Self Multi Call functions
	function multiCall(
		bytes[] calldata data
	) external returns (bytes[] memory results);

	// View Functions
	function projects(uint64 projectId) external view returns (Project memory);

	function pools(uint64 poolId) external view returns (Pool memory);

	function acceptedVAssets(address _vAsset) external view returns (bool);

	function nextProjectId() external view returns (uint64);

	function nextPoolId() external view returns (uint64);

	function owner() external view returns (address);
}
