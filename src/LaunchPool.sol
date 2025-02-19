// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LaunchPool is Ownable, ReentrancyGuard {
	/////////////////////////////////////////////////////////////////
	//////////////////////// CONTRACT STATES ///////////////////////
	///////////////////////////////////////////////////////////////

	/////////////////////////////////////////////////////////////////
	//////////////////////// CONTRACT EVENTS ///////////////////////
	///////////////////////////////////////////////////////////////

	/////////////////////////////////////////////////////////////////
	////////////////// VALIDATE POOL INFO ERRORS ///////////////////
	///////////////////////////////////////////////////////////////
	error StartTimeMustBeInFuture();
	error EndTimeMustBeAfterStartTime();
	error InvalidProjectTokenAddress();
	error InvalidAcceptedVAssetAddress();
	error TotalProjectTokensMustBeGreaterThanZero();
	error MaxAndMinTokensPerStakerMustBeGreaterThanZero();
	error MaxTokensPerStakerMustBeGreaterThanMin();

	//////////////////////////////////////////////////////////////////////////
	/////////////////////////////// MODIFIERS ///////////////////////////////
	////////////////////////////////////////////////////////////////////////
	modifier validTimeFrame(uint256 _startTime, uint256 _endTime) {
		if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
		if (_endTime <= _startTime) revert EndTimeMustBeAfterStartTime();
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

	constructor(
		address _projectOwner,
		address _projectToken,
		address _acceptedVAsset,
		uint256 _startTime,
		uint256 _endTime,
		uint256 _maxVTokensPerStaker,
		uint256 _minVTokensPerStaker
	) Ownable(_projectOwner) {
		_initValidation(
			_projectToken,
			_acceptedVAsset,
			_startTime,
			_endTime,
			_maxVTokensPerStaker,
			_minVTokensPerStaker
		);
	}

	function _initValidation(
		address _projectToken,
		address _acceptedVAsset,
		uint256 _startTime,
		uint256 _endTime,
		uint256 _maxVTokensPerStaker,
		uint256 _minVTokensPerStaker
	)
		internal
		view
		validTimeFrame(_startTime, _endTime)
		validTokenAddresses(_projectToken, _acceptedVAsset)
		validStakingRange(_maxVTokensPerStaker, _minVTokensPerStaker)
		returns (bool)
	{
		return true;
	}
}
