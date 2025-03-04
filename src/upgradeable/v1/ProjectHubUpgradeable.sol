// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { SelfMultiCall } from "@src/common/utils/SelfMultiCall.sol";

contract ProjectHubUpgradeable is
	Initializable,
	OwnableUpgradeable,
	UUPSUpgradeable,
	SelfMultiCall
{
	// Type definitions
	/**
	 * @dev Enum representing different pool types in the Defrost platform.
	 * @todo Additional pool types can be added after consensus among the team
	 * LAUNCHPOOL: For initial token offerings with time-based distribution
	 * LAUNCHPAD: For token sale events with specific allocation rules
	 * VESTING: For token distribution with time-locked release schedules
	 * FARMING: For yield generation and staking rewards
	 */
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

	// States
	mapping(uint64 => Project) public projects;
	mapping(uint64 => Pool) public pools;
	mapping(address => bool) public acceptedVAssets;
	uint64 public nextProjectId;
	uint64 public nextPoolId;

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
	event ProjectListingChanged(
		uint64 indexed projectId,
		bool indexed isListed
	);

	// Errors
	error NotProjectOwner();
	error ProjectNotFound();
	error PoolNotFound();
	error NotAcceptedVAsset();
	error StartBlockAfterEndBlock();
	error ChangeBlocksEmissionRatesMismatch();

	// Modifiers
	modifier onlyProjectOwner(uint64 _projectId) {
		if (projects[_projectId].projectOwner != msg.sender) {
			revert NotProjectOwner();
		}
		_;
	}

	modifier projectExists(uint64 _projectId) {
		if (projects[_projectId].projectId == 0) {
			revert ProjectNotFound();
		}
		_;
	}

	modifier poolExists(uint64 _poolId) {
		if (pools[_poolId].poolId == 0) {
			revert PoolNotFound();
		}
		_;
	}

	// Upgradeable Constructor
	function initialize(
		address _initialOwner,
		address[] calldata _initialVAssets
	) external initializer {
		__Ownable_init(_initialOwner);

		uint256 assetCount = _initialVAssets.length;
		for (uint256 i = 0; i < assetCount; i++) {
			acceptedVAssets[_initialVAssets[i]] = true;
		}

		nextProjectId = 1;
		nextPoolId = 1;
	}

	// Functions
	function createProject() external {
		uint64 projectId = nextProjectId;
		projects[projectId] = Project(projectId, msg.sender);
		emit ProjectCreated(projectId, msg.sender);
		++nextProjectId;
	}

	function listPool(
		uint64 _poolId
	) external poolExists(_poolId) onlyProjectOwner(pools[_poolId].projectId) {
		// No-op if already listed
		if (pools[_poolId].isListed == true) {
			return;
		}

		_setPoolListing(_poolId, true);
	}

	function unlistProject(
		uint64 _poolId
	) external poolExists(_poolId) onlyProjectOwner(pools[_poolId].projectId) {
		// No-op if already unlisted
		if (pools[_poolId].isListed == false) {
			return;
		}

		_setPoolListing(_poolId, false);
	}

	function createLaunchpool(
		LaunchpoolCreationParams memory _params
	) external returns (uint64 poolId) {
		address poolAddress = address(
			new Launchpool(
				_msgSender(),
				_params.projectToken,
				_params.vAsset,
				_params.startBlock,
				_params.endBlock,
				_params.maxVTokensPerStaker,
				_params.changeBlocks,
				_params.emissionRateChanges
			)
		);

		poolId = nextPoolId;
		pools[poolId] = Pool(
			poolId,
			PoolType.LAUNCHPOOL,
			poolAddress,
			_params.projectId,
			_params.isListed
		);

		emit PoolCreated(
			_params.projectId,
			PoolType.LAUNCHPOOL,
			poolId,
			_params.projectToken,
			_params.vAsset,
			poolAddress,
			_params.startBlock,
			_params.endBlock
		);

		++nextPoolId;
		return poolId;
	}

	function setAcceptedVAsset(
		address _vAsset,
		bool _isAccepted
	) external onlyOwner {
		acceptedVAssets[_vAsset] = _isAccepted;
	}

	/**
	 *
	 * @dev not sure if whether to keep this functionality
	 * @param _projectId .
	 * @param _isListed .
	 */
	function _setPoolListing(
		uint64 _projectId,
		bool _isListed
	) internal projectExists(_projectId) {
		pools[_projectId].isListed = _isListed;
		emit ProjectListingChanged(_projectId, _isListed);
	}

	/**
	 * @dev Required for UUPS implementation
	 * @dev Implementation to add support for multi-party authorization
	 * It mitigates single point of failure in case the owner key is compromised.
	 * For now, just leave it empty
	 */
	function _authorizeUpgrade(
		address newImplementation
	) internal override onlyOwner {}
}
