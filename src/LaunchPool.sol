// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LaunchPool is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	struct Staker {
		uint256 amount;
		uint256 nativeTokenAmount;
		uint256 claimOffset;
	}

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
	function stake(uint256 _amount) external {
		Staker storage investor = stakers[msg.sender];

		_tick();

		if (investor.amount > 0) {
			uint256 claimableProjectTokenAmount = (investor.amount *
				cumulativeExchangeRate) - investor.claimOffset;

			if (claimableProjectTokenAmount > 0) {
				projectToken.safeTransfer(
					address(msg.sender),
					claimableProjectTokenAmount
				);
			}
		}

		if (_amount > 0) {
			investor.amount += _amount;
			acceptedVAsset.safeTransferFrom(
				address(msg.sender),
				address(this),
				_amount
			);
			/**
			 * TODO: implement native amount increase here
			 */
		}

		investor.claimOffset = investor.amount * cumulativeExchangeRate;

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
		return (maxVTokensPerStaker, maxStakers);
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

		if (investor.amount == 0) {
			return 0;
		}

		return
			investor.amount *
			(cumulativeExchangeRate + _getCumulativeExchangeRate()) -
			investor.claimOffset;
	}

	function _tick() internal {
		if (block.number <= tickBlock) {
			return;
		}

		if (acceptedVAsset.balanceOf(address(this)) == 0) {
			tickBlock = block.number;
			_updateLastProcessedIndex();
			return;
		}

		cumulativeExchangeRate += _getCumulativeExchangeRate();
		tickBlock = block.number;
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
		uint256 periodStartBlock = tickBlock;
		uint256 len = changeBlocks.length;
		uint256 accumulatedIncrease = 0;

		for (uint256 i = lastProcessedChangeBlockIndex; i < len; i++) {
			uint256 periodEndBlock = changeBlocks[i];

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

		if (periodStartBlock < currentBlock) {
			uint256 finalDelta = _getTickBlockDelta(
				periodStartBlock,
				currentBlock
			);
			uint256 finalEmissionRate = getEmissionRate();
			accumulatedIncrease +=
				(finalEmissionRate * finalDelta) /
				stakedVAssetSupply;
		}

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
