// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LaunchPool} from "./LaunchPool.sol";

contract LaunchPoolFactory is Ownable {
    /////////////////////////////////////////////////////////////////
    //////////////////////// CONTRACT STATES ///////////////////////
    ///////////////////////////////////////////////////////////////
    // Counter for pool IDs
    uint256 private _nextPoolId;

    // Mapping from pool ID => pool address
    mapping(uint256 => address) public pools;

    // Mapping from project pool address => is valid/not valid || Check whether the pool is derived from this contract
    mapping(address => bool) poolIsValid;

    /////////////////////////////////////////////////////////////////
    //////////////////////// CONTRACT ERRORS ///////////////////////
    ///////////////////////////////////////////////////////////////
    error InvalidPoolId();
    error StartTimeMustBeInFuture();
    error EndTimeMustBeAfterStartTime();
    error InvalidProjectTokenAddress();
    error InvalidAcceptedVAssetAddress();
    error InvalidTokenAmount();

    /////////////////////////////////////////////////////////////////
    //////////////////////// CONTRACT EVENTS ///////////////////////
    ///////////////////////////////////////////////////////////////
    event PoolCreated(
        uint256 indexed poolId,
        address indexed projectOwner,
        address indexed projectToken,
        address acceptedVAsset,
        address poolAddress,
        uint256 startTime,
        uint256 endTime
    );

    constructor() Ownable(_msgSender()) {
        _nextPoolId = 1; // Start pool IDs from 1
    }

    function createPool(
        address _projectToken,
        address _acceptedVAsset,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _totalProjectTokens,
        uint256 _maxVTokensPerStaker,
        uint256 _minVTokensPerStaker
    ) public returns (uint256 poolId) {
        _initValidation(
            _projectToken,
            _acceptedVAsset,
            _startTime,
            _endTime,
            _totalProjectTokens,
            _maxVTokensPerStaker,
            _minVTokensPerStaker
        );

        poolId = _nextPoolId++;

        address poolAddress = address(
            new LaunchPool(
                _msgSender(),
                _projectToken,
                _acceptedVAsset,
                _startTime,
                _endTime,
                _totalProjectTokens,
                _maxVTokensPerStaker,
                _minVTokensPerStaker
            )
        );

        pools[poolId] = poolAddress;
        poolIsValid[poolAddress] = true;

        emit PoolCreated(
            poolId,
            msg.sender,
            _projectToken,
            _acceptedVAsset,
            poolAddress,
            _startTime,
            _endTime
        );

        return poolId;
    }

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

    //////////////////////////////////////////////////////////////////////////
    //////////////////////// REGULAR VIEW FUNCTIONS /////////////////////////
    ////////////////////////////////////////////////////////////////////////
    function getPoolAddress(
        uint256 poolId
    ) public view isValidPoolId(poolId) returns (address) {
        return pools[poolId];
    }

    function isPoolValid(address poolAddress) public view returns (bool) {
        return poolIsValid[poolAddress];
    }

    function getPoolCount() public view returns (uint256) {
        return _nextPoolId - 1;
    }

    //////////////////////////////////////////////////////////////////////////
    /////////////////////////////// MODIFIERS ///////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    modifier isValidPoolId(uint256 poolId) {
        if (poolId >= _nextPoolId) {
            revert InvalidPoolId();
        }
        _;
    }
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
        if (
            (_totalProjectTokens == 0 ||
                _maxVTokensPerStaker == 0 ||
                _minVTokensPerStaker == 0) ||
            (_maxVTokensPerStaker < _minVTokensPerStaker)
        ) revert InvalidTokenAmount();
        _;
    }
}
