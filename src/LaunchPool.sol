// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LaunchPool is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	/////////////////////////////////////////////////////////////////////////////////
	//////////////////////////////// CONTRACT STATES ///////////////////////////////
	///////////////////////////////////////////////////////////////////////////////
	uint256 public cumulativeExchangeRate;
	uint128 public startBlock;
	uint128 public endBlock;
	uint256 public maxVTokensPerStaker;
	uint256 public maxStakers;

	mapping(uint128 => uint256) public emissionRateChanges;
	uint128[] public changeBlocks;

	IERC20 public projectToken;
	IERC20 public acceptedVAsset;

	///////////////////////////////////////////////////////////////////////////////
	/////////////////////////////// CONTRACT EVENTS //////////////////////////////
	/////////////////////////////////////////////////////////////////////////////
	event Staked(address indexed user, uint256 amount);
	event Unstaked(address indexed user, uint256 amount);

	/////////////////////////////////////////////////////////////////////////////
	//////////////////////// VALIDATE POOL INFO ERRORS /////////////////////////
	///////////////////////////////////////////////////////////////////////////
	error startBlockMustBeInFuture();
	error endBlockMustBeAfterstartBlock();
	error InvalidProjectTokenAddress();
	error InvalidAcceptedVAssetAddress();
	error TotalProjectTokensMustBeGreaterThanZero();
	error MaxAndMinTokensPerStakerMustBeGreaterThanZero();
	error MaxTokensPerStakerMustBeGreaterThanMin();

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// MODIFIERS ///////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	modifier validTimeFrame(uint128 _startBlock, uint128 _endBlock) {
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

	modifier notProjectToken(address _tokenAddress) {
		require(
			_tokenAddress != address(projectToken),
			"Project token cannot be recovered"
		);
		_;
	}

	modifier afterPoolEnd() {
		require(block.number >= endBlock, "Pool is still active");
		_;
	}

	///////////////////////////////////////////////////////////////////////////
	/////////////////////////////// CONSTRUCTOR //////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	constructor(
		address _projectOwner,
		address _projectToken,
		address _acceptedVAsset,
		uint128 _startBlock,
		uint128 _endBlock,
		uint256 _maxVTokensPerStaker,
		uint256 _minVTokensPerStaker,
		uint128[] memory _changeBlocks,
		uint256[] memory _emissionRateChanges
	) Ownable(_projectOwner) {
		_initValidation(
			_projectToken,
			_acceptedVAsset,
			_startBlock,
			_endBlock,
			_maxVTokensPerStaker,
			_minVTokensPerStaker
		);

		projectToken = IERC20(_projectToken);
		acceptedVAsset = IERC20(_acceptedVAsset);
		startBlock = _startBlock;
		endBlock = _endBlock;

		uint256 len = _changeBlocks.length;
		require(len > 0, "No emission rate changes provided");
		require(_emissionRateChanges.length == len, "Arrays length mismatch");

		unchecked {
			for (uint256 i = 0; i < len; ++i) {
				emissionRateChanges[_changeBlocks[i]] = _emissionRateChanges[i];
			}
		}
		changeBlocks = _changeBlocks;
	}

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// FUNCTION ////////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	function stake() public {}
	function unstake() public nonReentrant {}
	function recoverWrongToken(
		address _tokenAddress
	) public onlyOwner notProjectToken(_tokenAddress) {
		IERC20 token = IERC20(_tokenAddress);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(owner(), balance);
	}

	function unstakeWithoutProjectToken() public nonReentrant {}

	function _tick() internal {}
	function _getTickBlockDelta(
		uint256 from,
		uint256 to
	) internal view returns (uint256) {
		if (to < endBlock) {
			return to - from;
		} else if (from >= endBlock) {
			return 0;
		}
		return endBlock - from;
	}

	function claimLeftOverProjectToken() public onlyOwner afterPoolEnd {
		uint256 balance = projectToken.balanceOf(address(this));
		projectToken.safeTransfer(owner(), balance);
	}

	///////////////////////////////////////////////////////////////////////////
	///////////////////////////// VIEW FUNCTION //////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	function getProjectToken() public view returns (address) {
		return address(projectToken);
	}

	function getAcceptedVAsset() public view returns (address) {
		return address(acceptedVAsset);
	}

	function getTotalStake() public view returns (uint256) {
		return acceptedVAsset.balanceOf(address(this));
	}

	function getTotalProjectToken() public view returns (uint256) {
		return projectToken.balanceOf(address(this));
	}

	function getStakingRange() public view returns (uint256, uint256) {
		return (maxVTokensPerStaker, maxStakers);
	}

	function getEmissionRate() public view returns (uint256) {
		uint256 currentBlock = block.number;
		uint256 emissionRate = 0;
		uint256 len = changeBlocks.length;
		for (uint256 i = 0; i < len; ++i) {
			if (currentBlock < changeBlocks[i]) {
				break;
			}
			emissionRate = emissionRateChanges[changeBlocks[i]];
		}
		return emissionRate;
	}

	function claimableProjectToken(
		address investor
	) public view returns (uint256) {}

	///////////////////////////////////////////////////////////////////////////
	/////////////////////// INITIALIZE MODIFIER HELPER ///////////////////////
	/////////////////////////////////////////////////////////////////////////
	function _initValidation(
		address _projectToken,
		address _acceptedVAsset,
		uint128 _startBlock,
		uint128 _endBlock,
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
