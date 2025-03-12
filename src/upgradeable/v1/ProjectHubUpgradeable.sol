// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SelfMultiCall } from "@src/utils/SelfMultiCall.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library PoolTypeLib {
	enum PoolType {
		LAUNCHPOOL,
		LAUNCHPAD,
		VESTING,
		FARMING
	}
}

/**
 * @title ProjectLibrary
 * @dev Library containing project management logic for ProjectHubUpgradeable
 */
library ProjectLibrary {
	struct Project {
		uint64 projectId;
		address projectOwner;
		// Always add new fields at the end
	}

	// Events
	event ProjectCreated(
		uint64 indexed projectId,
		address indexed projectOwner
	);

	// Errors
	error ProjectNotFound();
	error NotProjectOwner();

	/**
	 * @dev Creates a new project and assigns ownership to the caller
	 * @param projects Mapping of projects
	 * @param nextProjectId Current project ID counter
	 * @param sender Address of the caller
	 * @return projectId The ID of the newly created project
	 * @return newNextProjectId The updated project ID counter
	 */
	function createProject(
		mapping(uint64 => Project) storage projects,
		uint64 nextProjectId,
		address sender
	) external returns (uint64 projectId, uint64 newNextProjectId) {
		projectId = nextProjectId;
		projects[projectId] = Project(projectId, sender);
		emit ProjectCreated(projectId, sender);
		unchecked {
			newNextProjectId = nextProjectId + 1;
		}
	}

	/**
	 * @dev Validates if a project exists
	 * @param projects Mapping of projects
	 * @param projectId The project ID to validate
	 */
	function validateProjectExists(
		mapping(uint64 => Project) storage projects,
		uint64 projectId
	) public view {
		if (projects[projectId].projectId == 0) {
			revert ProjectNotFound();
		}
	}

	/**
	 * @dev Validates if the caller is the owner of a project
	 * @param projects Mapping of projects
	 * @param projectId The project ID to validate
	 * @param sender Address of the caller
	 */
	function validateProjectOwner(
		mapping(uint64 => Project) storage projects,
		uint64 projectId,
		address sender
	) public view {
		validateProjectExists(projects, projectId);
		if (projects[projectId].projectOwner != sender) {
			revert NotProjectOwner();
		}
	}
}

/**
 * @title PoolLibrary
 * @dev Library containing pool management logic for ProjectHubUpgradeable
 */
library LaunchpoolLibrary {
	struct Pool {
		uint64 poolId;
		PoolTypeLib.PoolType poolType;
		address poolAddress;
		uint64 projectId;
		bool isListed;
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
		bool isListed;
	}

	// Events
	event LaunchpoolCreated(
		uint64 indexed projectId,
		PoolTypeLib.PoolType indexed poolType,
		uint64 poolId,
		address projectToken,
		address indexed vAsset,
		address poolAddress,
		uint128 startBlock,
		uint128 endBlock
	);

	event PoolListingChanged(uint64 indexed projectId, bool indexed isListed);

	// Errors
	error PoolNotFound();

	/**
	 * @dev Creates a new launchpool
	 * @param pools Mapping of pools
	 * @param nextPoolId Current pool ID counter
	 * @param params Parameters for launchpool creation
	 * @param projectOwner Address of the caller
	 * @return poolId The ID of the newly created pool
	 * @return newNextPoolId The updated pool ID counter
	 * @return poolAddress The address of the created launchpool contract
	 */
	function createLaunchpool(
		mapping(uint64 => Pool) storage pools,
		uint64 nextPoolId,
		address nativeAsset,
		LaunchpoolCreationParams calldata params,
		address projectOwner
	)
		external
		returns (uint64 poolId, uint64 newNextPoolId, address poolAddress)
	{
		// Create a new launchpool and new launchpool record
		poolAddress = address(
			new Launchpool(
				projectOwner,
				params.projectToken,
				params.vAsset,
				nativeAsset,
				params.startBlock,
				params.endBlock,
				params.maxVTokensPerStaker,
				params.changeBlocks,
				params.emissionRateChanges
			)
		);

		// Transfer project tokens from project owner to launchpool
		// TODO: add tests for this
		IERC20(params.projectToken).transferFrom(
			projectOwner,
			poolAddress,
			params.projectTokenAmount
		);

		// Register pool in storage
		poolId = nextPoolId;
		pools[poolId] = Pool(
			poolId,
			PoolTypeLib.PoolType.LAUNCHPOOL,
			poolAddress,
			params.projectId,
			params.isListed
		);

		emit LaunchpoolCreated(
			params.projectId,
			PoolTypeLib.PoolType.LAUNCHPOOL,
			poolId,
			params.projectToken,
			params.vAsset,
			poolAddress,
			params.startBlock,
			params.endBlock
		);

		unchecked {
			newNextPoolId = nextPoolId + 1;
		}
	}

	/**
	 * @dev Sets the listing status of a pool
	 * @param pools Mapping of pools
	 * @param poolId The pool ID to update
	 * @param isListed The new listing status
	 */
	function setPoolListing(
		mapping(uint64 => Pool) storage pools,
		uint64 poolId,
		bool isListed
	) external {
		validatePoolExists(pools, poolId);

		pools[poolId].isListed = isListed;
		emit PoolListingChanged(pools[poolId].projectId, isListed);
	}

	/**
	 * @dev Validates if a pool exists
	 * @param pools Mapping of pools
	 * @param poolId The pool ID to validate
	 */
	function validatePoolExists(
		mapping(uint64 => Pool) storage pools,
		uint64 poolId
	) public view {
		if (pools[poolId].poolId == 0) {
			revert PoolNotFound();
		}
	}
}

/**
 * @title ProjectHubUpgradeable
 * @dev Main contract for managing projects and pools on the Defrost platform
 * This implementation uses libraries to reduce bytecode size
 */
contract ProjectHubUpgradeable is
	Initializable,
	OwnableUpgradeable,
	SelfMultiCall
{
	// Using libraries
	// using ProjectLibrary for mapping(uint64 => ProjectLibrary.Project);
	// using LaunchpoolLibrary for mapping(uint64 => LaunchpoolLibrary.Pool);
	using ProjectLibrary for *;
	using LaunchpoolLibrary for *;

	// State variables
	mapping(uint64 => ProjectLibrary.Project) public projects;
	mapping(uint64 => LaunchpoolLibrary.Pool) public pools;
	mapping(address => address) public vAssetToNativeAsset;
	uint64 public nextProjectId;
	uint64 public nextPoolId;

	// Events
	event VAssetMappingUpdated(
		address indexed vAsset,
		address indexed nativeAsset
	);

	// Custom Errors
	error AddressZero();
	error TokensArraysLengthMismatch();

	modifier notZeroAddress(address _address) {
		if (_address == address(0)) {
			revert AddressZero();
		}
		_;
	}

	/**
	 * @dev Initializes the contract with owner and initial accepted vAssets
	 * @param _initialOwner Address of the initial contract owner
	 * @param _initialVAssets Array of initially accepted vAsset addresses
	 */
	function initialize(
		address _initialOwner,
		address[] calldata _initialVAssets,
		address[] calldata _initialNativeAssets
	) external initializer {
		__Ownable_init(_initialOwner);

		uint256 vAssetCount = _initialVAssets.length;
		if (vAssetCount != _initialNativeAssets.length) {
			revert TokensArraysLengthMismatch();
		}

		for (uint256 i = 0; i < vAssetCount; ++i) {
			vAssetToNativeAsset[_initialVAssets[i]] = _initialNativeAssets[i];
		}

		nextProjectId = 1;
		nextPoolId = 1;
	}

	/**
	 * @dev Creates a new project and assigns ownership to the caller
	 */
	function createProject() external {
		(, uint64 newNextProjectId) = ProjectLibrary.createProject(
			projects,
			nextProjectId,
			_msgSender()
		);
		nextProjectId = newNextProjectId;
	}

	// /**
	//  * @dev Lists a pool, making it visible to the platform
	//  * @param _poolId ID of the pool to list
	//  */
	// function listPool(uint64 _poolId) external {
	// 	// Verify pool exists
	// 	LaunchpoolLibrary.validatePoolExists(pools, _poolId);

	// 	// Verify caller is project owner
	// 	ProjectLibrary.validateProjectOwner(
	// 		projects,
	// 		pools[_poolId].projectId,
	// 		_msgSender()
	// 	);

	// 	// No-op if already listed
	// 	if (pools[_poolId].isListed == true) {
	// 		return;
	// 	}

	// 	LaunchpoolLibrary.setPoolListing(pools, _poolId, true);
	// }

	// /**
	//  * @dev Unlists a pool, hiding it from the platform
	//  * @param _poolId ID of the pool to unlist
	//  */
	// function unlistPool(uint64 _poolId) external {
	// 	// Verify pool exists
	// 	LaunchpoolLibrary.validatePoolExists(pools, _poolId);

	// 	// Verify caller is project owner
	// 	ProjectLibrary.validateProjectOwner(
	// 		projects,
	// 		pools[_poolId].projectId,
	// 		_msgSender()
	// 	);

	// 	// No-op if already unlisted
	// 	if (pools[_poolId].isListed == false) {
	// 		return;
	// 	}

	// 	LaunchpoolLibrary.setPoolListing(pools, _poolId, false);
	// }

	/**
	 * @dev Creates a new launchpool
	 * @param _params Parameters for launchpool creation
	 * @return The ID of the newly created pool
	 */
	function createLaunchpool(
		LaunchpoolLibrary.LaunchpoolCreationParams calldata _params
	) external returns (uint64) {
		// Get native asset and verify vAsset is accepted
		address nativeAsset = vAssetToNativeAsset[_params.vAsset];
		if (nativeAsset == address(0)) {
			revert LaunchpoolLibrary.NotAcceptedVAsset();
		}

		address projectOwner = _msgSender();

		// Verify caller is project owner
		ProjectLibrary.validateProjectOwner(
			projects,
			_params.projectId,
			projectOwner
		);

		(uint64 poolId, uint64 newNextPoolId, ) = LaunchpoolLibrary
			.createLaunchpool(
				pools,
				nextPoolId,
				nativeAsset,
				_params,
				projectOwner
			);

		nextPoolId = newNextPoolId;
		return poolId;
	}

	/**
	 * @dev Sets whether a vAsset is accepted for pools
	 * @param _vAsset Address of the vAsset
	 * @param _nativeAsset Address of the native asset
	 */
	function setNativeAssetForVAsset(
		address _vAsset,
		address _nativeAsset
	) external notZeroAddress(_vAsset) notZeroAddress(_nativeAsset) onlyOwner {
		vAssetToNativeAsset[_vAsset] = _nativeAsset;

		emit VAssetMappingUpdated(_vAsset, _nativeAsset);
	}

	function removeVAssetSupport(
		address _vAsset
	) external notZeroAddress(_vAsset) onlyOwner {
		delete vAssetToNativeAsset[_vAsset];
		emit VAssetMappingUpdated(_vAsset, address(0));
	}

	function _msgSender() internal view override returns (address sender) {
		sender = _getMultiCallSender();
		return sender != address(0) ? sender : super._msgSender();
	}
}
