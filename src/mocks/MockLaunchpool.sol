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
	{}

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
		uint128 _nativeExRateSampleCount
	) external {
		nativeExRateSampleCount = _nativeExRateSampleCount;
	}

	function wild_updateNativeTokenExchangeRate(
		uint256 _nativeAmount,
		uint256 _vTokenAmount
	) external {
		_updateNativeTokenExchangeRate(_nativeAmount, _vTokenAmount);
	}

	function wild_setLastNativeExRateUpdateBlock(
		uint128 _lastNativeExRateUpdateBlock
	) external {
		lastNativeExRateUpdateBlock = _lastNativeExRateUpdateBlock;
	}

	// Expose internal methods for testing
	function exposed_getVTokenByTokenWithoutFee(
		uint256 _nativeAmount
	) public view returns (uint256) {
		return _getVTokenByTokenWithoutFee(_nativeAmount);
	}

	function exposed_getTokenByVTokenWithoutFee(
		uint256 _vTokenAmount
	) public view returns (uint256) {
		return _getTokenByVTokenWithoutFee(_vTokenAmount);
	}

	function exposed_getEstimatedNativeExRateAtEnd()
		public
		view
		returns (uint256)
	{
		return _getEstimatedNativeExRateAtEnd();
	}

	function exposed_getTokenDecimals(
		address _tokenAddress
	) public view returns (uint8) {
		return _getTokenDecimals(_tokenAddress);
	}

	function exposed_getActiveBlockDelta(
		uint256 from,
		uint256 to
	) public view returns (uint256) {
		return _getActiveBlockDelta(from, to);
	}

	function getPendingExchangeRate() public view returns (uint256) {
		return _getPendingExchangeRate();
	}

	function getClaimableProjectToken() public view returns (uint256) {
		return getClaimableProjectToken();
	}

	function _getVTokenByTokenWithoutFee(
		uint256 _nativeAmount
	) internal view override returns (uint256 vAssetAmount) {
		return
			// Temporary solution
			xcmOracle.getVTokenByToken(
				address(acceptedNativeAsset),
				_nativeAmount
			);
	}

	function _getTokenByVTokenWithoutFee(
		uint256 _vAssetAmount
	) internal view override returns (uint256 nativeAmount) {
		// Temporary solution
		return
			xcmOracle.getTokenByVToken(
				address(acceptedNativeAsset),
				_vAssetAmount
			);
	}

	function _preInit() internal override {
		MockXCMOracle _xcmOracle = new MockXCMOracle();
		xcmOracle = IXCMOracle(address(_xcmOracle));
	}
}
/* solhint-enable */
