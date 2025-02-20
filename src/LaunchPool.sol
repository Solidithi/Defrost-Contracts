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
	uint256 public tickBlock;
	uint256 public maxVTokensPerStaker;
	uint256 public maxStakers;

	uint256 public lastProcessedChangeBlockIndex;

	/**
	 * TODO: change to our withdraw address, this currently implement as the factory which is not ideal
	 */
	address public platformAdminAddress;
	uint256 public ownerShareOfInterest = 70; // 70% of the interest goes to the project owner, this is temp value
	// @todo: decide how much decimal should we take, this will affect some value

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
	error ArraysLengthMismatch();
	error NoEmissionRateChangesProvided();

	/////////////////////////////////////////////////////////////////////////////
	//////////////////////// OTHER ERRORS //////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////
	error ProjectTokenNotRecoverable();
	error MustBeAfterPoolEnd();
	error NotPlatformAdmin();

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// MODIFIERS ///////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	modifier validTokenAddress(address _tokenAdrees) {
		if (_tokenAdrees == address(0)) {
			revert InvalidAcceptedVAssetAddress();
		}
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
		if (_tokenAddress == address(acceptedVAsset)) {
			revert ProjectTokenNotRecoverable();
		}
		_;
	}

	modifier afterPoolEnd() {
		if (block.number < endBlock) {
			revert MustBeAfterPoolEnd();
		}
		_;
	}

	modifier onlyPlatformAdmin() {
		if (msg.sender != platformAdminAddress) {
			revert NotPlatformAdmin();
		}
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
	)
		Ownable(_projectOwner)
		validTokenAddress(_projectToken)
		validTokenAddress(_acceptedVAsset)
		validStakingRange(_maxVTokensPerStaker, _minVTokensPerStaker)
	{
		if (_startBlock <= block.timestamp) revert startBlockMustBeInFuture();
		if (_endBlock <= _startBlock) revert endBlockMustBeAfterstartBlock();

		uint256 len = _changeBlocks.length;
		if (len <= 0) {
			revert NoEmissionRateChangesProvided();
		}

		if (_emissionRateChanges.length != len) {
			revert ArraysLengthMismatch();
		}

		unchecked {
			for (uint256 i = 0; i < len; ++i) {
				emissionRateChanges[_changeBlocks[i]] = _emissionRateChanges[i];
			}
		}
		changeBlocks = _changeBlocks;

		platformAdminAddress = msg.sender;
		projectToken = IERC20(_projectToken);
		acceptedVAsset = IERC20(_acceptedVAsset);
		startBlock = _startBlock;
		endBlock = _endBlock;
	}

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// FUNCTION ////////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	function stake() external {}

	function unstake() external nonReentrant {}

	function recoverWrongToken(
		address _tokenAddress
	) external onlyOwner notProjectToken(_tokenAddress) {
		IERC20 token = IERC20(_tokenAddress);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(owner(), balance);
	}

	function unstakeWithoutProjectToken() external nonReentrant {}

	function claimLeftoverProjectToken() external onlyOwner afterPoolEnd {
		uint256 balance = projectToken.balanceOf(address(this));
		projectToken.safeTransfer(owner(), balance);
	}

	function claimOwnerInterest() external onlyOwner nonReentrant afterPoolEnd {
		uint256 balance = (acceptedVAsset.balanceOf(address(this)) *
			ownerShareOfInterest) / 100;
		acceptedVAsset.safeTransfer(owner(), balance);
	}

	function claimPlatformInterest()
		external
		onlyPlatformAdmin
		nonReentrant
		afterPoolEnd
	{
		uint256 balance = (acceptedVAsset.balanceOf(address(this)) *
			(100 - ownerShareOfInterest)) / 100;
		acceptedVAsset.safeTransfer(platformAdminAddress, balance);
	}

	function getPoolInfo()
		external
		view
		returns (uint128, uint128, uint256, uint256)
	{
		return (
			startBlock,
			endBlock,
			getTotalProjectToken(),
			getEmissionRate()
		);
	}

	// function getProjectToken() public view returns (address) {
	// 	return address(projectToken);
	// }

	// function getAcceptedVAsset() public view returns (address) {
	// 	return address(acceptedVAsset);
	// }

	function getTotalStaked() public view returns (uint256) {
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

	function getClaimableProjectToken(
		address investor
	) public view returns (uint256) {}

	function _tick() internal {
		if (block.number <= endBlock) {
			return;
		}

		uint256 stakedVAssetSupply = getTotalStaked();

		if (stakedVAssetSupply == 0) {
			tickBlock = block.number;
			_updateLastProcessedIndex();
			return;
		}

		uint256 currentBlock = block.number;
		uint256 tickBlockDelta = _getTickBlockDelta(tickBlock, currentBlock);
		uint256 emissionRate = getEmissionRate();
		cumulativeExchangeRate +=
			(emissionRate * tickBlockDelta) /
			stakedVAssetSupply;
		tickBlock = currentBlock;
		_updateLastProcessedIndex();
	}

	function _updateLastProcessedIndex() internal {
		uint256 len = changeBlocks.length;
		for (uint256 i = lastProcessedChangeBlockIndex; i < len; i++) {
			if (changeBlocks[i] > tickBlock) {
				break;
			}
			lastProcessedChangeBlockIndex = i;
		}
	}

	/**
	 * @dev Comment: read https://defrostian.atlassian.net/browse/SCRUM-87
	 * @notice 🔥🔥 SCRUM-87 should be marked completed when this function is implemented
	 * and adapts to the changning emissionRate
	 */
	function _getCumulativeExchangeRate() internal view returns (uint256) {
		if (block.number <= endBlock) {
			return cumulativeExchangeRate;
		}

		uint256 stakedVAssetSupply = getTotalStaked();
		if (stakedVAssetSupply == 0) {
			return cumulativeExchangeRate;
		}

		uint256 currentBlock = block.number;
		uint256 accumulatedRate = cumulativeExchangeRate;
		uint256 tickBlock = tickBlock;
		uint256 len = changeBlocks.length;

		for (uint256 i = lastProcessedChangeBlockIndex; i < len; i++) {
			uint256 changeBlock = changeBlocks[i];

			if (changeBlock >= currentBlock) {
				break;
			}

			uint256 periodEndBlock = changeBlock;
			uint256 tickBlockDelta = _getTickBlockDelta(
				tickBlock,
				periodEndBlock
			);

			uint256 emissionRate = i == 0
				? emissionRateChanges[changeBlocks[0]]
				: emissionRateChanges[changeBlocks[i - 1]];

			accumulatedRate +=
				(emissionRate * tickBlockDelta) /
				stakedVAssetSupply;

			tickBlock = changeBlock;
		}

		if (tickBlock < currentBlock) {
			uint256 finalDelta = _getTickBlockDelta(tickBlock, currentBlock);
			uint256 finalEmissionRate = getEmissionRate();
			accumulatedRate +=
				(finalEmissionRate * finalDelta) /
				stakedVAssetSupply;
		}

		return accumulatedRate;
	}

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

	///////////////////////////////////////////////////////////////////////////
	/////////////////////// INITIALIZE MODIFIER HELPER ///////////////////////
	/////////////////////////////////////////////////////////////////////////
	// function _initValidation(
	// 	address _projectToken,
	// 	address _acceptedVAsset,
	// 	uint128 _startBlock,
	// 	uint128 _endBlock,
	// 	uint256 _maxVTokensPerStaker,
	// 	uint256 _minVTokensPerStaker
	// )
	// 	internal
	// 	view
	// 	validTimeFrame(_startBlock, _endBlock)
	// 	validTokenAddresses(_projectToken, _acceptedVAsset)
	// 	validStakingRange(_maxVTokensPerStaker, _minVTokensPerStaker)
	// 	returns (bool)
	// {
	// 	return true;
	// }
}
