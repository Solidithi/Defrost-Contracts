// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { LaunchPool } from "./LaunchPool.sol";

contract LaunchPoolFactory is Ownable {
	/////////////////////////////////////////////////////////////////
	//////////////////////// CONTRACT STATES ///////////////////////
	///////////////////////////////////////////////////////////////
	// Counter for pool IDs
	uint256 private _nextPoolId;

	// Mapping from pool ID => pool address
	mapping(uint256 => address) public pools;

	// Mapping from project pool address => is valid/not valid || Check whether the pool is derived from this contract
	mapping(address => bool) internal _poolIsValid;

	/////////////////////////////////////////////////////////////////
	//////////////////////// CONTRACT EVENTS ///////////////////////
	///////////////////////////////////////////////////////////////
	event PoolCreated(
		uint256 indexed poolId,
		address indexed projectOwner,
		address indexed projectToken,
		address acceptedVAsset,
		address poolAddress,
		uint256 startBlock,
		uint256 endBlock
	);

	/////////////////////////////////////////////////////////////////
	//////////////////////// CONTRACT ERRORS ///////////////////////
	///////////////////////////////////////////////////////////////
	error InvalidPoolId();
	error startBlockMustBeInFuture();
	error endBlockMustBeAfterstartBlock();
	error InvalidProjectTokenAddress();
	error InvalidAcceptedVAssetAddress();
	error MaxAndMinTokensPerStakerMustBeGreaterThanZero();
	error MaxTokensPerStakerMustBeGreaterThanMin();

	//////////////////////////////////////////////////////////////////////////
	/////////////////////////////// MODIFIERS ///////////////////////////////
	////////////////////////////////////////////////////////////////////////
	modifier isValidPoolId(uint256 poolId) {
		if (poolId >= _nextPoolId) {
			revert InvalidPoolId();
		}
		_;
	}
	modifier validTimeFrame(uint256 _startBlock, uint256 _endBlock) {
		if (_startBlock <= block.timestamp) revert startBlockMustBeInFuture();
		if (_endBlock <= _startBlock) revert endBlockMustBeAfterstartBlock();
		_;
	}

	modifier validTokenAddresses(
		address _projectToken,
		address _acceptedVAsset
	) {
		if (_projectToken == address(0)) revert InvalidProjectTokenAddress();
		if (_acceptedVAsset == address(0))
			revert InvalidAcceptedVAssetAddress();
		_;
	}

	modifier validStakingRange(
		uint256 _maxVTokensPerStaker,
		uint256 _minVTokensPerStaker
	) {
		if (_maxVTokensPerStaker == 0 || _minVTokensPerStaker == 0)
			revert MaxAndMinTokensPerStakerMustBeGreaterThanZero();
		if (_maxVTokensPerStaker < _minVTokensPerStaker)
			revert MaxTokensPerStakerMustBeGreaterThanMin();
		_;
	}

	constructor() Ownable(_msgSender()) {
		_nextPoolId = 1; // Start pool IDs from 1
	}

	function createPool(
		address _projectToken,
		address _acceptedVAsset,
		uint128 _startBlock,
		uint128 _endBlock,
		uint256 _maxVTokensPerStaker,
		uint256 _minVTokensPerStaker
	) public returns (uint256 poolId) {
		_initValidation(
			_projectToken,
			_acceptedVAsset,
			_startBlock,
			_endBlock,
			_maxVTokensPerStaker,
			_minVTokensPerStaker
		);

		poolId = _nextPoolId++;

		address poolAddress = address(
			new LaunchPool(
				_msgSender(),
				_projectToken,
				_acceptedVAsset,
				_startBlock,
				_endBlock,
				_maxVTokensPerStaker,
				_minVTokensPerStaker
			)
		);

		pools[poolId] = poolAddress;
		_poolIsValid[poolAddress] = true;

		emit PoolCreated(
			poolId,
			msg.sender,
			_projectToken,
			_acceptedVAsset,
			poolAddress,
			_startBlock,
			_endBlock
		);

		return poolId;
	}

	//////////////////////////////////////////////////////////////////////////
	//////////////////////// REGULAR VIEW FUNCTIONS /////////////////////////
	////////////////////////////////////////////////////////////////////////
	function getPoolAddress(
		uint256 poolId
	) public view isValidPoolId(poolId) returns (address) {
		return pools[poolId];
	}

	function isPoolValid(address poolAddress) public view returns (bool) {
		return _poolIsValid[poolAddress];
	}

	function getPoolCount() public view returns (uint256) {
		return _nextPoolId - 1;
	}

	function _initValidation(
		address _projectToken,
		address _acceptedVAsset,
		uint256 _startBlock,
		uint256 _endBlock,
		uint256 _maxVTokensPerStaker,
		uint256 _minVTokensPerStaker
	)
		internal
		view
		validTimeFrame(_startBlock, _endBlock)
		validTokenAddresses(_projectToken, _acceptedVAsset)
		validStakingRange(_maxVTokensPerStaker, _minVTokensPerStaker)
		returns (bool)
	{
		return true;
	}
}
