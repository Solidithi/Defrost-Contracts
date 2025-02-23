// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Launchpool } from "./Launchpool.sol";

contract MoonbeamLaunchpoolFactory is Ownable {
	/////////////////////////////////////////////////////////////////
	//////////////////////// CONTRACT STATES ///////////////////////
	///////////////////////////////////////////////////////////////
	// Counter for pool IDs
	uint256 private _nextPoolId;

	// Mapping from vAsset address => is valid/not valid
	mapping(address => bool) public acceptedVAssets;

	// Mapping from pool ID => pool address
	mapping(uint256 => address) internal _pools;

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
	error InvalidVAsset(address vAsset);
	error InvalidBlockRange(uint128 startBlock, uint128 endBlock);
	error InvalidArrayLengths();

	//////////////////////////////////////////////////////////////////////////
	/////////////////////////////// MODIFIERS ///////////////////////////////
	////////////////////////////////////////////////////////////////////////
	modifier isValidPoolId(uint256 poolId) {
		if (poolId >= _nextPoolId) {
			revert InvalidPoolId();
		}
		_;
	}

	/**
	 * @dev vAsset addresses last updated on 23rd Feb 2022
	 */
	constructor() Ownable(_msgSender()) {
		_nextPoolId = 1; // Start pool IDs from 1

		// Moonbeam vAssets that are accepted
		acceptedVAssets[0xFFFfffFf15e1b7E3dF971DD813Bc394deB899aBf] = true; // vDOT
		acceptedVAssets[0xFfFfFFff99dABE1a8De0EA22bAa6FD48fdE96F6c] = true; // vGLMR
		acceptedVAssets[0xFffFffff55C732C47639231a4C4373245763d26E] = true; // vASTR
		acceptedVAssets[0xFffffFffCd0aD0EA6576B7b285295c85E94cf4c1] = true; // vFIL
	}

	function createPools(
		address projectToken,
		address[] calldata vAssets,
		uint128 startBlock,
		uint128 endBlock,
		uint256 maxVTokensPerStaker,
		uint128[] calldata changeBlocks,
		uint256[] calldata emissionRateChanges
	) public returns (uint256[] memory poolIds) {
		if (startBlock >= endBlock) {
			revert InvalidBlockRange(startBlock, endBlock);
		}
		if (changeBlocks.length != emissionRateChanges.length) {
			revert InvalidArrayLengths();
		}

		uint256 assetCount = vAssets.length;
		poolIds = new uint256[](assetCount);

		for (uint256 i; i < assetCount; ) {
			if (!acceptedVAssets[vAssets[i]]) {
				revert InvalidVAsset(vAssets[i]);
			}

			poolIds[i] = _createPool(
				projectToken,
				vAssets[i],
				startBlock,
				endBlock,
				maxVTokensPerStaker,
				changeBlocks,
				emissionRateChanges
			);

			unchecked {
				++i;
			}
		}
	}

	//////////////////////////////////////////////////////////////////////////
	//////////////////////// REGULAR VIEW FUNCTIONS /////////////////////////
	////////////////////////////////////////////////////////////////////////
	function getPoolAddress(
		uint256 poolId
	) public view isValidPoolId(poolId) returns (address) {
		return _pools[poolId];
	}

	function isPoolValid(address poolAddress) public view returns (bool) {
		return _poolIsValid[poolAddress];
	}

	function getPoolCount() public view returns (uint256) {
		return _nextPoolId - 1;
	}

	//////////////////////////////////////////////////////////////////////////
	//////////////////////// INTERNAL FUNCTIONS /////////////////////////////
	////////////////////////////////////////////////////////////////////////

	function _createPool(
		address projectToken,
		address vAsset,
		uint128 startBlock,
		uint128 endBlock,
		uint256 maxVTokensPerStaker,
		uint128[] calldata changeBlocks,
		uint256[] calldata emissionRateChanges
	) internal returns (uint256) {
		uint256 poolId = _nextPoolId;
		unchecked {
			++_nextPoolId;
		}

		address poolAddress = address(
			new Launchpool(
				_msgSender(),
				projectToken,
				vAsset,
				startBlock,
				endBlock,
				maxVTokensPerStaker,
				changeBlocks,
				emissionRateChanges
			)
		);

		_pools[poolId] = poolAddress;
		_poolIsValid[poolAddress] = true;

		emit PoolCreated(
			poolId,
			msg.sender,
			projectToken,
			vAsset,
			poolAddress,
			startBlock,
			endBlock
		);

		return poolId;
	}
}
