// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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

    function _initValidation(
        address _projectToken,
        address _acceptedVAsset,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _totalProjectTokens,
        uint256 _maxVTokensPerStaker,
        uint256 _minVTokensPerStaker
    )
        internal
        view
        validTimeFrame(_startTime, _endTime)
        validAddresses(_projectToken, _acceptedVAsset)
        validTokenAmounts(
            _totalProjectTokens,
            _maxVTokensPerStaker,
            _minVTokensPerStaker
        )
        returns (bool)
    {
        return true;
    }

    constructor(
        address _projectOwner,
        address _projectToken,
        address _acceptedVAsset,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _totalProjectTokens,
        uint256 _maxVTokensPerStaker,
        uint256 _minVTokensPerStaker
    ) Ownable(_projectOwner) {
        _initValidation(
            _projectToken,
            _acceptedVAsset,
            _startTime,
            _endTime,
            _totalProjectTokens,
            _maxVTokensPerStaker,
            _minVTokensPerStaker
        );
    }

    //////////////////////////////////////////////////////////////////////////
    /////////////////////////////// MODIFIERS ///////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    modifier validTimeFrame(uint256 _startTime, uint256 _endTime) {
        if (_startTime <= block.timestamp) revert StartTimeMustBeInFuture();
        if (_endTime <= _startTime) revert EndTimeMustBeAfterStartTime();
        _;
    }

    modifier validAddresses(address _projectToken, address _acceptedVAsset) {
        if (_projectToken == address(0)) revert InvalidProjectTokenAddress();
        if (_acceptedVAsset == address(0))
            revert InvalidAcceptedVAssetAddress();
        _;
    }

    modifier validTokenAmounts(
        uint256 _totalProjectTokens,
        uint256 _maxVTokensPerStaker,
        uint256 _minVTokensPerStaker
    ) {
        if (_totalProjectTokens == 0)
            revert TotalProjectTokensMustBeGreaterThanZero();
        if (_maxVTokensPerStaker == 0 || _minVTokensPerStaker == 0)
            revert MaxAndMinTokensPerStakerMustBeGreaterThanZero();
        _;
    }
}
