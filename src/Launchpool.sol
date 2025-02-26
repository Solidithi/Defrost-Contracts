// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IXCMOracle } from "./interfaces/IXCMOracle.sol";

contract Launchpool is Ownable, ReentrancyGuard {
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

	uint256 public immutable SCALING_FACTOR;
	uint256 public constant MAX_DECIMALS = 30;
	uint256 public constant BASE_PRECISION = 1e30;
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
	IXCMOracle public xcmOracle =
		IXCMOracle(0xEF81930Aa8ed07C17948B2E26b7bfAF20144eF2a);

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
	error DecimalsTooHigh(); // 30 is the max
	error InvalidTokenDecimals(); // if decimals can't be fetched

	/////////////////////////////////////////////////////////////////////////////
	//////////////////////// OTHER ERRORS //////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////
	error ProjectTokenNotRecoverable();
	error MustBeAfterPoolEnd();
	error NotPlatformAdmin();
	error ZeroAmountNotAllowed();
	error ExceedsMaximumAllowedStakePerUser();
	error VAssetAmountNotSufficient();
	error NotEnoughVAssetToWithdraw();

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

	modifier nonZeroAmount(uint256 _amount) {
		if (_amount == 0) {
			revert ZeroAmountNotAllowed();
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
		if (_startBlock <= block.number) revert startBlockMustBeInFuture();
		if (_endBlock <= _startBlock) revert endBlockMustBeAfterstartBlock();

		uint256 len = _changeBlocks.length;
		if (len <= 0) {
			revert NoEmissionRateChangesProvided();
		}

		if (_emissionRateChanges.length != len) {
			revert ArraysLengthMismatch();
		}

		uint8 decimals;
		try IERC20Metadata(_projectToken).decimals() returns (uint8 dec) {
			decimals = dec;
		} catch {
			revert InvalidTokenDecimals();
		}

		if (decimals > MAX_DECIMALS) {
			revert DecimalsTooHigh();
		}

		SCALING_FACTOR = BASE_PRECISION / (10 ** decimals);

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
		maxVAssetPerStaker = _maxVAssetPerStaker;
		tickBlock = _startBlock;
	}

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// FUNCTION ////////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	function stake(
		uint256 _amount
	) external nonZeroAmount(_amount) nonReentrant {
		if (_amount > maxVAssetPerStaker) {
			revert ExceedsMaximumAllowedStakePerUser();
		}

		Staker storage investor = stakers[msg.sender];

		_tick();

		if (investor.vAssetAmount > 0) {
			uint256 claimableProjectTokenAmount = (investor.vAssetAmount *
				cumulativeExchangeRate) /
				SCALING_FACTOR -
				investor.claimOffset;

			if (claimableProjectTokenAmount > 0) {
				projectToken.safeTransfer(
					address(msg.sender),
					claimableProjectTokenAmount
				);
			}
		}

		investor.vAssetAmount += _amount;
		acceptedVAsset.safeTransferFrom(
			address(msg.sender),
			address(this),
			_amount
		);
		/**
		 * TODO: implement native amount increase here
		 */

		investor.claimOffset = investor.vAssetAmount * cumulativeExchangeRate;

		emit Staked(address(msg.sender), _amount);
	}

	function unstake(
		uint256 _amount
	) external nonZeroAmount(_amount) nonReentrant {
		//Transfer withdraw amount of vAsset
		// stakers[msg.sender].vAssetAmount -= _amount;
		// acceptedVAsset.safeTransfer(address(msg.sender), _amount);
		uint256 withdrawableNativeAmount = stakers[msg.sender]
			.nativeTokenAmount;
		uint256 withDrawableVAsset = xcmOracle.getVTokenByToken(
			address(acceptedVAsset),
			withdrawableNativeAmount
		); //DOT to vDOT amount
		if (withDrawableVAsset < _amount) {
			revert VAssetAmountNotSufficient();
		}

		stakers[msg.sender].vAssetAmount -= withDrawableVAsset;
		acceptedVAsset.safeTransfer(address(msg.sender), withDrawableVAsset);

		//Transfer Project Token reward
		uint256 withdrawProjectToken = projectToken.balanceOf(address(this));
		projectToken.safeTransfer(address(msg.sender), withdrawProjectToken);

		stakers[msg.sender].claimOffset =
			stakers[msg.sender].vAssetAmount *
			cumulativeExchangeRate;

		emit Unstaked(address(msg.sender), _amount);
	}

	function recoverWrongToken(
		address _tokenAddress
	) external onlyOwner notProjectToken(_tokenAddress) {
		IERC20 token = IERC20(_tokenAddress);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(owner(), balance);
	}

	function unstakeWithoutProjectToken() external nonReentrant {
		//Check if user have stake vAsset or not
		if (stakers[msg.sender].vAssetAmount == 0) {
			revert NotEnoughVAssetToWithdraw();
		}

		uint256 vAssetWithDrawAmount = stakers[msg.sender].vAssetAmount;
		stakers[msg.sender].vAssetAmount = 0;
		acceptedVAsset.safeTransfer(address(msg.sender), vAssetWithDrawAmount);
	}

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

	function setXCMOracleAddress(
		address _xcmOracleAddress
	) external onlyPlatformAdmin {
		xcmOracle = IXCMOracle(_xcmOracleAddress);
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
			(investor.vAssetAmount *
				(cumulativeExchangeRate + _getPendingExchangeRate())) /
			SCALING_FACTOR -
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

		cumulativeExchangeRate += _getPendingExchangeRate();
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

	function _getPendingExchangeRate() internal view returns (uint256) {
		uint256 stakedVAssetSupply = getTotalStaked();
		if (stakedVAssetSupply == 0) {
			return 0;
		}

		uint256 currentBlock = block.number;
		uint128 periodStartBlock = tickBlock;
		uint128 periodEndBlock;
		uint256 len = changeBlocks.length;
		uint256 accumulatedIncrease = 0;
		uint256 i = lastProcessedChangeBlockIndex;

		for (; i < len; i++) {
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
				(emissionRate * tickBlockDelta * SCALING_FACTOR) /
				stakedVAssetSupply;

			periodStartBlock = periodEndBlock;
		}

		uint256 finalDelta = _getTickBlockDelta(periodStartBlock, currentBlock);
		uint256 finalEmissionRate = periodEndBlock <= currentBlock
			? emissionRateChanges[periodEndBlock] // Get rate for the period that started at periodEndBlock
			: emissionRateChanges[changeBlocks[i - 1]]; // Get rate after the last processed change block
		accumulatedIncrease +=
			(finalEmissionRate * finalDelta * SCALING_FACTOR) /
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
