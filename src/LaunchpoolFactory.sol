// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Launchpool } from "./Launchpool.sol";

contract LaunchpoolFactory is Ownable {
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

	//////////////////////////////////////////////////////////////////////////
	/////////////////////////////// MODIFIERS ///////////////////////////////
	////////////////////////////////////////////////////////////////////////
	modifier isValidPoolId(uint256 poolId) {
		if (poolId >= _nextPoolId) {
			revert InvalidPoolId();
		}
		_;
	}

	constructor() Ownable(_msgSender()) {
		_nextPoolId = 1; // Start pool IDs from 1
	}

	function createPools(
		address _projectToken,
		address[] memory _acceptedVAssets,
		uint128 _startBlock,
		uint128 _endBlock,
		uint256 _maxVTokensPerStaker,
		uint128[] memory _changeBlocks,
		uint256[] memory _emissionRateChanges
	) public returns (uint256[] memory poolIds) {
		uint256 assetCount = _acceptedVAssets.length;
		poolIds = new uint256[](assetCount);

		for (uint256 i = 0; i < assetCount; i++) {
			uint256 poolId = _nextPoolId++;

			address poolAddress = address(
				new Launchpool(
					_msgSender(),
					_projectToken,
					_acceptedVAssets[i],
					_startBlock,
					_endBlock,
					_maxVTokensPerStaker,
					_changeBlocks,
					_emissionRateChanges
				)
			);

			pools[poolId] = poolAddress;
			_poolIsValid[poolAddress] = true;

			emit PoolCreated(
				poolId,
				msg.sender,
				_projectToken,
				_acceptedVAssets[i],
				poolAddress,
				_startBlock,
				_endBlock
			);

			poolIds[i] = poolId;
		}

		return poolIds;
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
}
