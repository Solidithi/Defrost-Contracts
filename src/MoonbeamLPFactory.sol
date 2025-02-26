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
	mapping(address => address) public vAssetToAsset;

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
		address acceptedNativeAsset,
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

	constructor() Ownable(_msgSender()) {
		_nextPoolId = 1; // Start pool IDs from 1
		vAssetToAsset[
			0xFFFfffFf15e1b7E3dF971DD813Bc394deB899aBf
		] = 0xFfFFfFff1FcaCBd218EDc0EbA20Fc2308C778080; // vDOT -> xcDOT
		vAssetToAsset[
			0xFfFfFFff99dABE1a8De0EA22bAa6FD48fdE96F6c
		] = 0x0000000000000000000000000000000000000802; // vGLMR -> GLMR
		vAssetToAsset[
			0xFffFffff55C732C47639231a4C4373245763d26E
		] = 0xFfFFFfffA893AD19e540E172C10d78D4d479B5Cf; // vASTR -> ASTR
		vAssetToAsset[
			0xFffffFffCd0aD0EA6576B7b285295c85E94cf4c1
		] = 0xfFFfFFFF6C57e17D210DF507c82807149fFd70B2; // vFIL -> Bifrost_Filecoin_Native_Token
	}

	function createPools(
		address projectToken,
		address[] calldata vAssets,
		address[] calldata nativeAssets,
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
			if (vAssetToAsset[vAssets[i]] == address(0)) {
				revert InvalidVAsset(vAssets[i]);
			}

			poolIds[i] = _createPool(
				projectToken,
				vAssets[i],
				nativeAssets[i],
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

	function addAcceptedVAsset(
		address vAsset,
		address nativeAsset
	) public onlyOwner {
		vAssetToAsset[vAsset] = nativeAsset;
	}

	function removeAcceptedVAsset(address vAsset) public onlyOwner {
		vAssetToAsset[vAsset] = address(0);
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
		address nativeAsset,
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
				nativeAsset,
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
			nativeAsset,
			poolAddress,
			startBlock,
			endBlock
		);

		return poolId;
	}
}
