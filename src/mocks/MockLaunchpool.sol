// SPDX-License-Identifier: MIT
/* solhint-disable */

pragma solidity ^0.8.26;

import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";
import { MockXCMOracle } from "../mocks/MockXCMOracle.sol";

contract MockLaunchpool is Launchpool {
	constructor(
		address _projectOwner,
		address _projectToken,
		address _acceptedVAsset,
		address _acceptedNativeAsset,
		uint128 _startBlock,
		uint128 _endBlock,
		uint256 _maxVAssetPerStaker,
		uint128[] memory _changeBlocks,
		uint256[] memory _emissionRateChanges
	)
		// address _xcmOracle
		Launchpool(
			_projectOwner,
			_projectToken,
			_acceptedVAsset,
			_acceptedNativeAsset,
			_startBlock,
			_endBlock,
			_maxVAssetPerStaker,
			_changeBlocks,
			_emissionRateChanges
		)
	{
			}

	// Wildcard setters for testing (beware when testing)
	function wild_setTickBlock(uint128 _tickBlock) external {
		tickBlock = _tickBlock;
	}

	function wild_setLastNativeExRate(uint256 _lastNativeExRate) external {
		lastNativeExRate = _lastNativeExRate;
	}

	function wild_setAvgNativeExRateGradient(
		uint256 _avgNativeExRateGradient
	) external {
		avgNativeExRateGradient = _avgNativeExRateGradient;
	}

	function wild_setNativeExRateSampleCount(
		uint256 _nativeExRateSampleCount
	) external {
		nativeExRateSampleCount = _nativeExRateSampleCount;
	}

	// Expose internal methods for testing
	function exposed_updateNativeTokenExchangeRate(
		uint256 _nativeAmount,
		uint256 _vTokenAmount
	) external {
		_updateNativeTokenExchangeRate(_nativeAmount, _vTokenAmount);
	}

	function getPendingExchangeRate() public view returns (uint256) {
		return _getPendingExchangeRate();
	}

	function getClaimableProjectToken() public view returns (uint256) {
		return getClaimableProjectToken();
	}

	function _preInit() internal override {
		MockXCMOracle _xcmOracle = new MockXCMOracle();
		xcmOracle = IXCMOracle(address(_xcmOracle));
	}
}
/* solhint-enable */
