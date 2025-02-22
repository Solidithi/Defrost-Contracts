// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LaunchPool is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	struct Staker {
		uint256 vAssetAmount;
		uint256 nativeTokenAmount;
		uint256 claimOffset;
	}

	/////////////////////////////////////////////////////////////////////////////////
	//////////////////////////////// CONTRACT STATES ///////////////////////////////
	///////////////////////////////////////////////////////////////////////////////
	uint256 public cumulativeExchangeRate;
	uint128 public startBlock;
	uint128 public endBlock;
	uint128 public tickBlock;
	uint128 public ownerShareOfInterest = 70; // 70% of the interest goes to the project owner, this is temp value
	uint256 public maxVAssetPerStaker;
	uint256 public maxStakers;

	uint256 public lastProcessedChangeBlockIndex;

	/**
	 * TODO: change to our withdraw address, this currently implement as the factory which is not ideal
	 */
	address public platformAdminAddress;
	// @todo: decide how much decimal should we take, this will affect some value

	mapping(uint128 => uint256) public emissionRateChanges;
	uint128[] public changeBlocks;

	IERC20 public projectToken;
	IERC20 public acceptedVAsset;

	mapping(address => Staker) public stakers;

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
	error InvalidAcceptedVAssetAddress();
	error TotalProjectTokensMustBeGreaterThanZero();
	error MaxAndMinTokensPerStakerMustBeGreaterThanZero();
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

	modifier validStakingRange(uint256 _maxVAssetPerStaker) {
		if (_maxVAssetPerStaker == 0)
			revert MaxAndMinTokensPerStakerMustBeGreaterThanZero();
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
		uint256 _maxVAssetPerStaker,
		uint128[] memory _changeBlocks,
		uint256[] memory _emissionRateChanges
	)
		Ownable(_projectOwner)
		validTokenAddress(_projectToken)
		validTokenAddress(_acceptedVAsset)
		validStakingRange(_maxVAssetPerStaker)
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
	function stake(uint256 _amount) external {
		Staker storage investor = stakers[msg.sender];

		_tick();

		if (investor.vAssetAmount > 0) {
			uint256 claimableProjectTokenAmount = (investor.vAssetAmount *
				cumulativeExchangeRate) - investor.claimOffset;

			if (claimableProjectTokenAmount > 0) {
				projectToken.safeTransfer(
					address(msg.sender),
					claimableProjectTokenAmount
				);
			}
		}

		if (
			_amount > 0 && investor.vAssetAmount + _amount <= maxVAssetPerStaker
		) {
			investor.vAssetAmount += _amount;
			acceptedVAsset.safeTransferFrom(
				address(msg.sender),
				address(this),
				_amount
			);
			/**
			 * TODO: implement native amount increase here
			 */
		}

		investor.claimOffset = investor.vAssetAmount * cumulativeExchangeRate;

		emit Staked(address(msg.sender), _amount);
	}

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

	function getTotalStaked() public view returns (uint256) {
		return acceptedVAsset.balanceOf(address(this));
	}

	function getTotalProjectToken() public view returns (uint256) {
		return projectToken.balanceOf(address(this));
	}

	function getStakingRange() public view returns (uint256, uint256) {
		return (maxVAssetPerStaker, maxStakers);
	}

	function getEmissionRate() public view returns (uint256) {
		/**
		 * TODO: should make this into a modifier for launchpool end scenario
		 */
		if (block.number >= endBlock) {
			return 0;
		}

		uint256 currentBlock = block.number;
		uint256 emissionRate = 0;
		uint256 len = changeBlocks.length;
		for (uint256 i = lastProcessedChangeBlockIndex; i < len; ++i) {
			if (currentBlock < changeBlocks[i]) {
				break;
			}
			emissionRate = emissionRateChanges[changeBlocks[i]];
		}
		return emissionRate;
	}

	function getClaimableProjectToken(
		address _investor
	) public view returns (uint256) {
		Staker memory investor = stakers[_investor];

		if (investor.vAssetAmount == 0) {
			return 0;
		}

		return
			investor.vAssetAmount *
			(cumulativeExchangeRate + _getCumulativeExchangeRate()) -
			investor.claimOffset;
	}

	function _tick() internal {
		if (block.number <= tickBlock) {
			return;
		}

		if (acceptedVAsset.balanceOf(address(this)) == 0) {
			unchecked {
				tickBlock = uint128(block.number);
			}
			_updateLastProcessedIndex();
			return;
		}

		cumulativeExchangeRate += _getCumulativeExchangeRate();
		unchecked {
			tickBlock = uint128(block.number);
		}
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

	function _getCumulativeExchangeRate() internal view returns (uint256) {
		uint256 stakedVAssetSupply = getTotalStaked();
		if (stakedVAssetSupply == 0) {
			return 0;
		}

		uint256 currentBlock = block.number;
		uint128 periodStartBlock = tickBlock;
		uint128 periodEndBlock;
		uint256 len = changeBlocks.length;
		uint256 accumulatedIncrease = 0;

		for (uint256 i = lastProcessedChangeBlockIndex; i < len; i++) {
			periodEndBlock = changeBlocks[i];

			if (periodEndBlock >= currentBlock) {
				break;
			}

			if (periodEndBlock <= periodStartBlock) {
				continue;
			}

			uint256 tickBlockDelta = _getTickBlockDelta(
				periodStartBlock,
				periodEndBlock
			);

			uint256 emissionRate = emissionRateChanges[
				i == 0 ? changeBlocks[0] : changeBlocks[i - 1]
			];

			accumulatedIncrease +=
				(emissionRate * tickBlockDelta) /
				stakedVAssetSupply;

			periodStartBlock = periodEndBlock;
		}

		uint256 finalDelta = _getTickBlockDelta(periodStartBlock, currentBlock);
		uint256 finalEmissionRate = periodEndBlock <= currentBlock
			? emissionRateChanges[periodEndBlock] // Get rate for the period that started at periodEndBlock
			: emissionRateChanges[periodStartBlock]; // Get rate after the last processed change block
		accumulatedIncrease +=
			(finalEmissionRate * finalDelta) /
			stakedVAssetSupply;

		return accumulatedIncrease;
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
}
