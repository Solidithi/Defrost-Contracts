// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/**
 * @title IProjectHub
 * @notice Interface for the ProjectHubUpgradeable contract
 * @dev This interface is self-contained without external dependencies for easier integration with tools like Remix IDE
 */
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
	}

	struct LaunchpoolCreationParams {
		uint64 projectId;
		uint256 projectTokenAmount;
		address projectToken;
		address vAsset;
		uint128 startBlock;
		uint128 endBlock;
		uint256 maxVTokensPerStaker;
		uint128[] changeBlocks;
		uint256[] emissionRateChanges;
	}

	// Events
	event ProjectCreated(
		uint64 indexed projectId,
		address indexed projectOwner
	);
	event LaunchpoolCreated(
		uint64 indexed projectId,
		PoolType indexed poolType,
		uint64 poolId,
		address projectToken,
		address indexed vAsset,
		address poolAddress,
		uint128 startBlock,
		uint128 endBlock
	);
	event VAssetMappingUpdated(
		address indexed vAsset,
		address indexed nativeAsset
	);

	// Initialization & Admin Functions
	function initialize(
		address _initialOwner,
		address[] calldata _initialVAssets,
		address[] calldata _initialNativeAssets
	) external;

	function setNativeAssetForVAsset(
		address _vAsset,
		address _nativeAsset
	) external;

	function removeVAssetSupport(address _vAsset) external;

	// Project Management
	function createProject() external;

	// Pool Management
	function createLaunchpool(
		LaunchpoolCreationParams memory params
	) external returns (uint64);

	// Multi-call Functionality
	function selfMultiCall(
		bytes[] calldata data
	) external returns (bytes[] memory);

	// View Functions - State Variables
	function projects(uint64 projectId) external view returns (Project memory);

	function pools(uint64 poolId) external view returns (Pool memory);

	function vAssetToNativeAsset(
		address _vAsset
	) external view returns (address);

	function nextProjectId() external view returns (uint64);

	function nextPoolId() external view returns (uint64);

	function owner() external view returns (address);
}
