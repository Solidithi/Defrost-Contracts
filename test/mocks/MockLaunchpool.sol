// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Launchpool } from "@src/Launchpool.sol";
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
		// address _xcmOracle
	)
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
		// Do sth cool if u want
		MockXCMOracle _xcmOracle = new MockXCMOracle();
		xcmOracle = IXCMOracle(address(_xcmOracle));

	}

	function getPendingExchangeRate() public view returns (uint256) {
		return _getPendingExchangeRate();
	}
}
