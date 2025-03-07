// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SelfMultiCall } from "@src/utils/SelfMultiCall.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";

/**
 * @title ProjectLibrary
 * @dev Library containing project management logic for ProjectHubUpgradeable
 */
library ProjectLibrary {
	enum PoolType {
		LAUNCHPOOL,
		LAUNCHPAD,
		VESTING,
		FARMING
	}

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
	// Type definitions
	enum PoolType {
		LAUNCHPOOL,
		LAUNCHPAD,
		VESTING,
		FARMING
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

	event PoolListingChanged(uint64 indexed projectId, bool indexed isListed);

	// Errors
	error PoolNotFound();
	error NotAcceptedVAsset();
	error StartBlockAfterEndBlock();
	error ChangeBlocksEmissionRatesMismatch();

	/**
	 * @dev Creates a new launchpool
	 * @param pools Mapping of pools
	 * @param nextPoolId Current pool ID counter
	 * @param params Parameters for launchpool creation
	 * @param sender Address of the caller
	 * @return poolId The ID of the newly created pool
	 * @return newNextPoolId The updated pool ID counter
	 * @return poolAddress The address of the created launchpool contract
	 */
	function createLaunchpool(
		mapping(uint64 => Pool) storage pools,
		uint64 nextPoolId,
		LaunchpoolCreationParams memory params,
		address sender
	)
		external
		returns (uint64 poolId, uint64 newNextPoolId, address poolAddress)
	{
		// Create new Launchpool contract
		poolAddress = address(
			new Launchpool(
				sender,
				params.projectToken,
				params.vAsset,
				params.startBlock,
				params.endBlock,
				params.maxVTokensPerStaker,
				params.changeBlocks,
				params.emissionRateChanges
			)
		);

		// Register pool in storage
		poolId = nextPoolId;
		pools[poolId] = Pool(
			poolId,
			PoolType.LAUNCHPOOL,
			poolAddress,
			params.projectId,
			params.isListed
		);

		emit PoolCreated(
			params.projectId,
			PoolType.LAUNCHPOOL,
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
	using ProjectLibrary for mapping(uint64 => ProjectLibrary.Project);
	using LaunchpoolLibrary for mapping(uint64 => LaunchpoolLibrary.Pool);

	// Type definitions directly imported from libraries
	enum PoolType {
		LAUNCHPOOL,
		LAUNCHPAD,
		VESTING,
		FARMING
	}

	// State variables
	mapping(uint64 => ProjectLibrary.Project) public projects;
	mapping(uint64 => LaunchpoolLibrary.Pool) public pools;
	mapping(address => bool) public acceptedVAssets;
	uint64 public nextProjectId;
	uint64 public nextPoolId;

	/**
	 * @dev Initializes the contract with owner and initial accepted vAssets
	 * @param _initialOwner Address of the initial contract owner
	 * @param _initialVAssets Array of initially accepted vAsset addresses
	 */
	function initialize(
		address _initialOwner,
		address[] calldata _initialVAssets
	) external initializer {
		__Ownable_init(_initialOwner);

		uint256 assetCount = _initialVAssets.length;
		for (uint256 i = 0; i < assetCount; ++i) {
			acceptedVAssets[_initialVAssets[i]] = true;
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

	/**
	 * @dev Lists a pool, making it visible to the platform
	 * @param _poolId ID of the pool to list
	 */
	function listPool(uint64 _poolId) external {
		// Verify pool exists
		LaunchpoolLibrary.validatePoolExists(pools, _poolId);

		// Verify caller is project owner
		ProjectLibrary.validateProjectOwner(
			projects,
			pools[_poolId].projectId,
			_msgSender()
		);

		// No-op if already listed
		if (pools[_poolId].isListed == true) {
			return;
		}

		LaunchpoolLibrary.setPoolListing(pools, _poolId, true);
	}

	/**
	 * @dev Unlists a pool, hiding it from the platform
	 * @param _poolId ID of the pool to unlist
	 */
	function unlistProject(uint64 _poolId) external {
		// Verify pool exists
		LaunchpoolLibrary.validatePoolExists(pools, _poolId);

		// Verify caller is project owner
		ProjectLibrary.validateProjectOwner(
			projects,
			pools[_poolId].projectId,
			_msgSender()
		);

		// No-op if already unlisted
		if (pools[_poolId].isListed == false) {
			return;
		}

		LaunchpoolLibrary.setPoolListing(pools, _poolId, false);
	}

	/**
	 * @dev Creates a new launchpool
	 * @param _params Parameters for launchpool creation
	 * @return poolId The ID of the newly created pool
	 */
	function createLaunchpool(
		LaunchpoolLibrary.LaunchpoolCreationParams memory _params
	) external returns (uint64 poolId) {
		// Verify vAsset is accepted
		if (!acceptedVAssets[_params.vAsset]) {
			revert LaunchpoolLibrary.NotAcceptedVAsset();
		}

		// Verify caller is project owner
		ProjectLibrary.validateProjectOwner(
			projects,
			_params.projectId,
			_msgSender()
		);

		// Create launchpool using library
		(poolId, nextPoolId, ) = LaunchpoolLibrary.createLaunchpool(
			pools,
			nextPoolId,
			_params,
			_msgSender()
		);

		return poolId;
	}

	/**
	 * @dev Sets whether a vAsset is accepted for pools
	 * @param _vAsset Address of the vAsset
	 * @param _isAccepted Whether the vAsset should be accepted
	 */
	function setAcceptedVAsset(
		address _vAsset,
		bool _isAccepted
	) external onlyOwner {
		acceptedVAssets[_vAsset] = _isAccepted;
	}

	function _msgSender() internal view override returns (address sender) {
		sender = _getMultiCallSender();
		return sender != address(0) ? sender : super._msgSender();
	}
}
