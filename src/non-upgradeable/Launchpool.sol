// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";

contract Launchpool is Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	struct Staker {
		uint256 nativeAmount;
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
	uint256 public totalNativeStake;

	uint256 public immutable SCALING_FACTOR;
	uint256 public constant MAX_DECIMALS = 30;
	uint256 public constant BASE_PRECISION = 1e30;
	uint256 public lastProcessedChangeBlockIndex;

	address public platformAdminAddress;

	mapping(uint128 => uint256) public emissionRateChanges;
	uint128[] public changeBlocks;

	IERC20 public projectToken;
	IERC20 public acceptedVAsset;
	IERC20 public acceptedNativeAsset; //For XCMOracle cal
	IXCMOracle public xcmOracle =
		IXCMOracle(0xEF81930Aa8ed07C17948B2E26b7bfAF20144eF2a);

	mapping(address => Staker) public stakers;

	// Last-recorded exchange rate between acceptedNativeAsset and acceptedVAsset
	uint256 public lastNativeExRate;
	// The numerator to calculate the weighted average gradient of the exchange rate (e.g. 100/block)
	uint256 public avgNativeExRateGradient;

	// Sample count
	uint256 public nativeExRateSampleCount;

	uint256 public immutable NATIVE_SCALING_FACTOR;

	uint256 public constant BLOCK_TIME = 6 seconds; // for Moonbeam

	///////////////////////////////////////////////////////////////////////////////
	/////////////////////////////// CONTRACT EVENTS //////////////////////////////
	/////////////////////////////////////////////////////////////////////////////
	event Staked(address indexed user, uint256 amount);
	event Unstaked(address indexed user, uint256 amount);

	/////////////////////////////////////////////////////////////////////////////
	//////////////////////// VALIDATE POOL INFO ERRORS /////////////////////////
	///////////////////////////////////////////////////////////////////////////
	error StartBlockMustBeInFuture();
	error EndBlockMustBeAfterstartBlock();
	error ZeroAddress();
	error FirstChangeBlockMustBeStartBlock();
	error TotalProjectTokensMustBeGreaterThanZero();
	error MaxAndMinTokensPerStakerMustBeGreaterThanZero();
	error ArraysLengthMismatch();
	error NoEmissionRateChangesProvided();
	error DecimalsTooHigh(address tokenAddress); // 30 is the max
	error FailedToReadTokenDecimals(); // if decimals can't be fetched

	/////////////////////////////////////////////////////////////////////////////
	//////////////////////// OTHER ERRORS //////////////////////////////////////
	///////////////////////////////////////////////////////////////////////////
	error ProjectTokenNotRecoverable();
	error MustBeAfterPoolEnd();
	error NotPlatformAdmin();
	error ZeroAmountNotAllowed();
	error ExceedsMaximumAllowedStakePerUser();
	error VAssetAmountNotSufficient();
	error NativeAmountExceedStake();
	error MustBeDuringPoolTime();

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// MODIFIERS ///////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	modifier validTokenAddress(address _tokenAdrees) {
		if (_tokenAdrees == address(0)) {
			revert ZeroAddress();
		}
		_;
	}

	modifier validStakingRange(uint256 _maxVAssetPerStaker) {
		if (_maxVAssetPerStaker == 0)
			revert MaxAndMinTokensPerStakerMustBeGreaterThanZero();
		_;
	}

	modifier notProjectToken(address _tokenAddress) {
		if (_tokenAddress == address(projectToken)) {
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

	modifier poolIsActive() {
		if (block.number < startBlock || block.number > endBlock) {
			revert MustBeDuringPoolTime();
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
		address _acceptedNativeAsset,
		uint128 _startBlock,
		uint128 _endBlock,
		uint256 _maxVAssetPerStaker,
		uint128[] memory _changeBlocks,
		uint256[] memory _emissionRateChanges
	)
		Ownable(_projectOwner)
		validTokenAddress(_projectToken) // TODO: add tests for these token validations
		validTokenAddress(_acceptedVAsset)
		validTokenAddress(_acceptedNativeAsset)
		validStakingRange(_maxVAssetPerStaker)
	{
		if (_startBlock <= block.number) revert StartBlockMustBeInFuture();
		if (_endBlock <= _startBlock) revert EndBlockMustBeAfterstartBlock();

		// Ensure the first change block matches the start block
		uint256 changeBlocksLen = _changeBlocks.length;
		if (changeBlocksLen <= 0) {
			revert NoEmissionRateChangesProvided();
		}

		// Consider adding this in Launchpool constructor
		// for (uint256 i = 1; i < changeBlocksLen; i++) {
		// 	if (_changeBlocks[i] <= _changeBlocks[i - 1]) {
		// 		revert ChangeBlocksNotInAscendingOrder();
		// 	}
		// }

		if (_changeBlocks[0] != _startBlock) {
			revert FirstChangeBlockMustBeStartBlock();
		}

		if (_emissionRateChanges.length != changeBlocksLen) {
			revert ArraysLengthMismatch();
		}

		// TODO: add tests for this
		uint8 pTokenDecimals = 18;
		try IERC20Metadata(_projectToken).decimals() returns (uint8 dec) {
			pTokenDecimals = dec;
			// TODO: add tests for this
			if (pTokenDecimals > MAX_DECIMALS) {
				revert DecimalsTooHigh(_projectToken);
			}
		} catch {
			revert FailedToReadTokenDecimals();
		}

		// TODO: add tests for this
		uint8 nativeDecimals = 18;
		try IERC20Metadata(_acceptedNativeAsset).decimals() returns (
			uint8 dec
		) {
			nativeDecimals = dec;
			// if (nativeDecimals > MAX_DECIMALS) { // not likely to happen
			// 	revert DecimalsTooHigh(_acceptedNativeAsset);
			// }
		} catch {
			revert FailedToReadTokenDecimals();
		}

		// TODO: add tests for this
		SCALING_FACTOR = BASE_PRECISION / (10 ** pTokenDecimals);

		// TODO: add tests for this
		NATIVE_SCALING_FACTOR = BASE_PRECISION / (10 ** nativeDecimals);

		unchecked {
			for (uint256 i = 0; i < changeBlocksLen; ++i) {
				emissionRateChanges[_changeBlocks[i]] = _emissionRateChanges[i];
			}
		}

		changeBlocks = _changeBlocks;
		platformAdminAddress = _msgSender();
		projectToken = IERC20(_projectToken);
		acceptedVAsset = IERC20(_acceptedVAsset);
		acceptedNativeAsset = IERC20(_acceptedNativeAsset);
		startBlock = _startBlock;
		endBlock = _endBlock;
		maxVAssetPerStaker = _maxVAssetPerStaker;
		tickBlock = _startBlock;
	}

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// FUNCTION ////////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	function stake(
		uint256 _vTokenAmount
	) external nonZeroAmount(_vTokenAmount) poolIsActive nonReentrant {
		if (_vTokenAmount > maxVAssetPerStaker) {
			revert ExceedsMaximumAllowedStakePerUser();
		}

		Staker storage investor = stakers[msg.sender];

		uint256 nativeAmount = xcmOracle.getTokenByVToken(
			address(acceptedNativeAsset),
			_vTokenAmount
		);

		_updateNativeTokenExchangeRate(nativeAmount, _vTokenAmount);

		_tick();

		if (investor.nativeAmount > 0) {
			uint256 claimableProjectTokenAmount = (investor.nativeAmount *
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

		investor.nativeAmount += nativeAmount;
		totalNativeStake += nativeAmount;

		acceptedVAsset.safeTransferFrom(
			address(msg.sender),
			address(this),
			_vTokenAmount
		);
		investor.claimOffset = investor.nativeAmount * cumulativeExchangeRate;

		emit Staked(address(msg.sender), _vTokenAmount);
	}

	function unstake(
		uint256 _vTokenAmount
	) external nonZeroAmount(_vTokenAmount) nonReentrant {
		address investorAddress = _msgSender();
		Staker storage investor = stakers[investorAddress];

		if (investor.nativeAmount == 0) {
			revert ZeroAmountNotAllowed();
		}

		uint256 withdrawableVAsset = getWithdrawableVAssets(
			investor.nativeAmount
		);

		if (withdrawableVAsset < _vTokenAmount) {
			revert VAssetAmountNotSufficient();
		}

		uint256 withdrawnNativeAmount = xcmOracle.getTokenByVToken(
			address(acceptedNativeAsset),
			_vTokenAmount
		);

		if (investor.nativeAmount < withdrawnNativeAmount) {
			revert NativeAmountExceedStake();
		}

		if (block.number <= endBlock) {
			_updateNativeTokenExchangeRate(
				withdrawnNativeAmount,
				_vTokenAmount
			);
		}

		_tick();

		uint256 exchangeRate = cumulativeExchangeRate;
		uint256 claimableProjectTokenAmount = ((investor.nativeAmount *
			exchangeRate) / SCALING_FACTOR) - investor.claimOffset;

		if (claimableProjectTokenAmount > 0) {
			projectToken.safeTransfer(
				address(msg.sender),
				claimableProjectTokenAmount
			);
		}

		uint256 remainingAmount = investor.nativeAmount - withdrawnNativeAmount;

		investor.claimOffset =
			(remainingAmount * exchangeRate) /
			SCALING_FACTOR;

		investor.nativeAmount = remainingAmount;
		totalNativeStake -= withdrawnNativeAmount;

		acceptedVAsset.safeTransfer(investorAddress, _vTokenAmount);

		emit Unstaked(investorAddress, _vTokenAmount);
	}

	function recoverWrongToken(
		address _tokenAddress
	) external onlyOwner notProjectToken(_tokenAddress) {
		IERC20 token = IERC20(_tokenAddress);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(owner(), balance);
	}

	// Need modification
	function unstakeWithoutProjectToken(
		uint256 _vTokenAmount
	) external nonReentrant {
		Staker storage investor = stakers[msg.sender];
		if (investor.nativeAmount == 0) {
			revert ZeroAmountNotAllowed();
		}

		uint256 withdrawableVAsset = xcmOracle.getVTokenByToken(
			address(acceptedNativeAsset),
			investor.nativeAmount
		);

		if (
			withdrawableVAsset <
			_vTokenAmount *
				10 ** IERC20Metadata(address(acceptedNativeAsset)).decimals()
		) {
			revert VAssetAmountNotSufficient();
		}

		_updateNativeTokenExchangeRate(investor.nativeAmount, _vTokenAmount);

		_tick();

		uint256 withdrawnNativeAmount = xcmOracle.getTokenByVToken(
			address(acceptedNativeAsset),
			_vTokenAmount
		);

		investor.nativeAmount -= withdrawnNativeAmount;
		totalNativeStake -= withdrawnNativeAmount;

		acceptedVAsset.safeTransfer(address(msg.sender), _vTokenAmount);
		investor.claimOffset = investor.nativeAmount * cumulativeExchangeRate;
		emit Unstaked(address(msg.sender), _vTokenAmount);
	}

	function claimLeftoverProjectToken() external onlyOwner afterPoolEnd {
		uint256 balance = projectToken.balanceOf(address(this));
		projectToken.safeTransfer(owner(), balance);
	}

	function claimOwnerInterest() external onlyOwner nonReentrant {
		(uint256 ownerClaims, ) = _getPlatformAndOwnerClaimableVAssets();
		acceptedVAsset.safeTransfer(owner(), ownerClaims);
	}

	function claimPlatformInterest() external onlyPlatformAdmin {
		(, uint256 platformClaims) = _getPlatformAndOwnerClaimableVAssets();
		acceptedVAsset.safeTransfer(platformAdminAddress, platformClaims);
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

	function getWithdrawableVAssets(
		uint256 nativeAmount
	) public view returns (uint256 withdrawableVAssets) {
		if (block.number <= endBlock) {
			withdrawableVAssets = xcmOracle.getVTokenByToken(
				address(acceptedNativeAsset),
				nativeAmount
			);
		} else {
			uint256 exRateAtEnd = _getEstimatedNativeExRateAtEnd();
			withdrawableVAssets =
				(nativeAmount * exRateAtEnd) /
				NATIVE_SCALING_FACTOR;
		}
	}

	function getTotalVAssetStaked() public view returns (uint256) {
		return acceptedVAsset.balanceOf(address(this));
	}

	function getTotalProjectToken() public view returns (uint256) {
		return projectToken.balanceOf(address(this));
	}

	/**
	 * TODO: Need review
	 */
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

		if (investor.nativeAmount == 0) {
			return 0;
		}

		return
			(investor.nativeAmount *
				(cumulativeExchangeRate + _getPendingExchangeRate())) /
			SCALING_FACTOR -
			investor.claimOffset;
	}

	function getStakerNativeAmount(
		address _investor
	) public view returns (uint256) {
		return stakers[_investor].nativeAmount;
	}

	function _tick() internal {
		if (block.number <= tickBlock) {
			return;
		}

		if (totalNativeStake == 0) {
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

	// TODO: need testing and validation
	function _updateNativeTokenExchangeRate(
		uint256 _nativeAmount,
		uint256 _vTokenAmount
	) internal {
		uint256 newNativeExRate = (_nativeAmount * NATIVE_SCALING_FACTOR) /
			_vTokenAmount;

		// Handle first call of pool then exit early
		if (lastNativeExRate == 0) {
			// Near impossible for this to happen
			lastNativeExRate = newNativeExRate;
			// avgNativeExRateGradient = newNativeExRate;
			// ++nativeExRateSampleCount;
			return;
		}

		uint256 currentBlock = block.number;
		uint256 blockDelta = currentBlock - tickBlock;
		if (blockDelta == 0) {
			return;
		}
		uint256 exRateDelta = (newNativeExRate > lastNativeExRate)
			? newNativeExRate - lastNativeExRate
			: 0;

		uint256 newGradientSample = exRateDelta / blockDelta;

		// Calculate rolling average of the gradient
		avgNativeExRateGradient =
			(avgNativeExRateGradient *
				nativeExRateSampleCount +
				newGradientSample) /
			(++nativeExRateSampleCount);

		lastNativeExRate = newNativeExRate;
	}

	function _getPendingExchangeRate() internal view returns (uint256) {
		if (totalNativeStake == 0) {
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

			uint256 tickBlockDelta = _getActiveBlockDelta(
				periodStartBlock,
				periodEndBlock
			);

			uint256 emissionRate = emissionRateChanges[
				i == 0 ? changeBlocks[0] : changeBlocks[i - 1]
			];

			accumulatedIncrease +=
				(emissionRate * tickBlockDelta * SCALING_FACTOR) /
				totalNativeStake;

			periodStartBlock = periodEndBlock;
		}

		uint256 finalDelta = _getActiveBlockDelta(
			periodStartBlock,
			currentBlock
		);
		uint256 finalEmissionRate = (periodEndBlock <= currentBlock)
			? emissionRateChanges[periodEndBlock] // Get rate for the period that started at periodEndBlock
			: emissionRateChanges[changeBlocks[i - 1]]; // Get rate after the last processed change block

		accumulatedIncrease +=
			(finalEmissionRate * finalDelta * SCALING_FACTOR) /
			totalNativeStake;

		return accumulatedIncrease;
	}

	function _getEstimatedNativeExRateAtEnd()
		internal
		view
		returns (
			// uint256 _currentBlock
			uint256 estimatedNativeExRateAtEnd
		)
	{
		uint blocksTilEnd = endBlock - tickBlock;
		estimatedNativeExRateAtEnd =
			lastNativeExRate +
			(avgNativeExRateGradient * blocksTilEnd);
	}

	function _getPlatformAndOwnerClaimableVAssets()
		internal
		view
		returns (uint256 ownerClaims, uint256 platformClaims)
	{
		uint256 allVAssets = acceptedVAsset.balanceOf(address(this));
		uint256 investorVAssets = getWithdrawableVAssets(totalNativeStake);

		uint256 combinedClaims = allVAssets - investorVAssets;
		ownerClaims = (combinedClaims * ownerShareOfInterest) / 100;
		platformClaims = combinedClaims - ownerClaims;
	}

	// TODO: add tests for this
	function _getActiveBlockDelta(
		uint256 from,
		uint256 to
	) internal view returns (uint256) {
		if (to <= endBlock) {
			return to - from;
		} else if (from >= endBlock) {
			return 0;
		}
		return endBlock - from;
	}
}
