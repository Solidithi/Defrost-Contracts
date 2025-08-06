// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";

contract Launchpool is Ownable, ReentrancyGuard, Pausable {
	using SafeERC20 for IERC20;

	struct Staker {
		uint256 nativeAmount;
		uint256 claimOffset;
	}

	struct PoolTokenomics {
		uint256 totalNativeStake;
		uint256 totalVTokenStake;
		uint256 projectTokenReserve;
		uint256 emissionRate;
		uint256 projectTokenExchangeRate;
		uint256 nativeTokenExchangeRate;
	}

	/////////////////////////////////////////////////////////////////////////////////
	//////////////////////////////// CONTRACT STATES ///////////////////////////////
	///////////////////////////////////////////////////////////////////////////////
	uint256 public cumulativeExchangeRate;
	uint128 public startBlock;
	uint128 public endBlock;
	uint128 public tickBlock;
	uint128 public ownerShareOfInterest = 90; // 90% of the interest goes to the PO, the rest is platform fee
	uint256 public maxTokenPerStaker;
	uint256 public maxStakers;
	uint256 public totalNativeStake;

	uint256 public immutable SCALING_FACTOR;
	uint256 public constant MAX_DECIMALS = 30;
	uint256 public constant BASE_PRECISION = 1e30;
	uint256 public lastProcessedChangeBlockIndex;

	address public platformAdminAddress =
		0xfD48761638E3a8C368ABAEFa9859cf6baa6C3c27;

	mapping(uint128 => uint256) public emissionRateChanges;
	uint128[] public changeBlocks;

	IERC20 public projectToken;
	IERC20 public acceptedVAsset;
	IERC20 public acceptedNativeAsset; //For XCMOracle cal
	IXCMOracle public xcmOracle;

	mapping(address => Staker) public stakers;

	// Last-recorded exchange rate between acceptedNativeAsset and acceptedVAsset
	uint256 public lastNativeExRate;
	// The numerator to calculate the weighted average gradient of the exchange rate (e.g. 100/block)
	uint256 public avgNativeExRateGradient;

	// Sample count
	uint128 public nativeExRateSampleCount;
	uint128 public lastNativeExRateUpdateBlock;

	uint256 public immutable ONE_VTOKEN;

	// TODO: add test for this
	bool public platformFeeClaimed;

	///////////////////////////////////////////////////////////////////////////////
	/////////////////////////////// CONTRACT EVENTS //////////////////////////////
	/////////////////////////////////////////////////////////////////////////////
	event Staked(address indexed user, uint256 amount);
	event Unstaked(address indexed user, uint256 amount);
	event ProjectTokensClaimed(address indexed user, uint256 amount); // @TODO: add tests for this
	event OwnerInterestsClaimed(
		address indexed claimer,
		uint256 ownerClaims,
		uint256 platformFee // this is identical to 'claimAmount' in PlatformFeeClaimed event
	);
	event PlatformFeeClaimed(address indexed claimer, uint256 platformFee);

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
	error ExceedMaxTokensPerStaker();
	error ExceedWithdrawableVTokens();
	error ExceedNativeStake();
	error MustBeDuringPoolTime();
	error PlatformFeeAlreadyClaimed();

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// MODIFIERS ///////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	modifier validTokenAddress(address _tokenAdrees) {
		if (_tokenAdrees == address(0)) {
			revert ZeroAddress();
		}
		_;
	}

	modifier validStakingRange(uint256 _maxTokenPerStaker) {
		if (_maxTokenPerStaker == 0)
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
		// TODO: re-validate this (just updated from < to <=)
		if (block.number <= endBlock) {
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

	modifier handleNativeExRateAfterEnd() {
		// Enforce update of avg. native exrate gradient if it's 0 after end
		if (avgNativeExRateGradient == 0 && block.number > endBlock) {
			uint256 nativePerVToken = _getTokenByVTokenWithoutFee(ONE_VTOKEN);
			_updateNativeTokenExchangeRate(nativePerVToken, ONE_VTOKEN);
		}
		_;
	}

	///////////////////////////////////////////////////////////////////////////
	/////////////////////////////// CONSTRUCTOR //////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	constructor(
		address xcmOracleAddress,
		address _projectOwner,
		address _projectToken,
		address _acceptedVAsset,
		address _acceptedNativeAsset,
		uint128 _startBlock,
		uint128 _endBlock,
		uint256 _maxTokenPerStaker,
		uint128[] memory _changeBlocks,
		uint256[] memory _emissionRateChanges
	)
		Ownable(_projectOwner)
		validTokenAddress(_projectToken)
		validTokenAddress(_acceptedVAsset)
		validTokenAddress(_acceptedNativeAsset)
		validStakingRange(_maxTokenPerStaker)
	{
		_preInit();
		xcmOracle = IXCMOracle(xcmOracleAddress);

		uint256 currentBlock = block.number;
		if (_startBlock <= currentBlock) revert StartBlockMustBeInFuture();
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

		uint8 pTokenDecimals = _getTokenDecimals(address(_projectToken));
		uint8 vAssetDecimals = _getTokenDecimals(address(_acceptedVAsset));

		SCALING_FACTOR = BASE_PRECISION / (10 ** pTokenDecimals);
		ONE_VTOKEN = 10 ** vAssetDecimals;

		unchecked {
			for (uint256 i = 0; i < changeBlocksLen; ++i) {
				emissionRateChanges[_changeBlocks[i]] = _emissionRateChanges[i];
			}
		}

		// Record native exchange rate at start block
		lastNativeExRate = _getTokenByVTokenWithoutFee(ONE_VTOKEN);
		++nativeExRateSampleCount;
		lastNativeExRateUpdateBlock = uint128(currentBlock);

		changeBlocks = _changeBlocks;
		projectToken = IERC20(_projectToken);
		acceptedVAsset = IERC20(_acceptedVAsset);
		acceptedNativeAsset = IERC20(_acceptedNativeAsset);
		startBlock = _startBlock;
		endBlock = _endBlock;
		maxTokenPerStaker = _maxTokenPerStaker;
		tickBlock = _startBlock;
	}

	///////////////////////////////////////////////////////////////////////////
	//////////////////////////////// FUNCTION ////////////////////////////////
	/////////////////////////////////////////////////////////////////////////
	function pause() external onlyPlatformAdmin {
		_pause();
	}

	function unpause() external onlyPlatformAdmin {
		_unpause();
	}

	function stake(
		uint256 _vTokenAmount
	)
		external
		nonZeroAmount(_vTokenAmount)
		poolIsActive
		whenNotPaused
		nonReentrant
	{
		address stakerAddr = _msgSender();
		Staker storage staker = stakers[stakerAddr];

		uint256 nativeAmount = _getTokenByVTokenWithoutFee(_vTokenAmount);

		if (staker.nativeAmount == 0) {
			if (nativeAmount > maxTokenPerStaker) {
				revert ExceedMaxTokensPerStaker();
			}
		} else if (staker.nativeAmount + nativeAmount > maxTokenPerStaker) {
			revert ExceedMaxTokensPerStaker();
		}

		_updateNativeTokenExchangeRate(nativeAmount, _vTokenAmount);

		_tick();

		if (staker.nativeAmount > 0) {
			uint256 claimableProjectTokenAmount = (staker.nativeAmount *
				cumulativeExchangeRate) /
				SCALING_FACTOR -
				staker.claimOffset;

			if (claimableProjectTokenAmount > 0) {
				projectToken.safeTransfer(
					address(msg.sender),
					claimableProjectTokenAmount
				);
				emit ProjectTokensClaimed(
					stakerAddr,
					claimableProjectTokenAmount
				);
			}
		}

		staker.nativeAmount += nativeAmount;
		totalNativeStake += nativeAmount;

		acceptedVAsset.safeTransferFrom(
			address(msg.sender),
			address(this),
			_vTokenAmount
		);

		staker.claimOffset =
			(staker.nativeAmount * cumulativeExchangeRate) /
			SCALING_FACTOR;

		emit Staked(address(msg.sender), _vTokenAmount);
	}

	function unstake(
		uint256 _vTokenAmount
	)
		external
		nonZeroAmount(_vTokenAmount)
		whenNotPaused
		nonReentrant
		handleNativeExRateAfterEnd
	{
		address stakerAddr = _msgSender();
		Staker memory staker = stakers[stakerAddr];
		uint256 withdrawnNativeTokens = _handleUnstakeAmount(
			staker,
			_vTokenAmount
		);

		_updateNativeTokenExchangeRate(staker.nativeAmount, _vTokenAmount);
		_tick();

		// Handle distribution of project tokens
		uint256 cumExRate = cumulativeExchangeRate;
		uint256 claimableProjectTokenAmount = ((staker.nativeAmount *
			cumExRate) / SCALING_FACTOR) - staker.claimOffset;

		if (claimableProjectTokenAmount > 0) {
			projectToken.safeTransfer(stakerAddr, claimableProjectTokenAmount);
			emit ProjectTokensClaimed(stakerAddr, claimableProjectTokenAmount);
		}

		uint256 remainingAmount = staker.nativeAmount - withdrawnNativeTokens;
		staker.claimOffset = (remainingAmount * cumExRate) / SCALING_FACTOR;
		staker.nativeAmount = remainingAmount;
		totalNativeStake -= withdrawnNativeTokens;

		// Write investor back to storage
		stakers[stakerAddr] = staker;

		emit Unstaked(stakerAddr, _vTokenAmount);

		acceptedVAsset.safeTransfer(stakerAddr, _vTokenAmount);
	}

	// Need modification
	/**
	 * @notice Emergency withdrawal function that works even when contract is paused
	 * @dev Users forfeit any earned project tokens when using this function
	 * @param _withdrawnVTokens Amount of vTokens to withdraw
	 */
	function unstakeWithoutProjectToken(
		uint256 _withdrawnVTokens
	) external nonZeroAmount(_withdrawnVTokens) nonReentrant {
		address stakerAddr = _msgSender();
		Staker memory staker = stakers[stakerAddr];

		uint256 withdrawnNativeTokens = _handleUnstakeAmount(
			staker,
			_withdrawnVTokens
		);

		_updateNativeTokenExchangeRate(staker.nativeAmount, _withdrawnVTokens);
		_tick();

		staker.nativeAmount -= withdrawnNativeTokens;
		staker.claimOffset =
			(staker.nativeAmount * cumulativeExchangeRate) /
			SCALING_FACTOR;
		totalNativeStake -= withdrawnNativeTokens;

		// Write staker back to storage
		stakers[stakerAddr] = staker;

		emit Unstaked(stakerAddr, _withdrawnVTokens);

		acceptedVAsset.safeTransfer(stakerAddr, _withdrawnVTokens);
	}

	/**
	 * @notice Allows stakers to claim earned project tokens without unstaking
	 * @dev Updates exchange rates and claim offset similar to stake/unstake functions
	 */
	function claimProjectTokens()
		external
		whenNotPaused
		nonReentrant
		handleNativeExRateAfterEnd
	{
		address stakerAddr = _msgSender();
		Staker memory staker = stakers[stakerAddr];

		if (staker.nativeAmount == 0) {
			revert ZeroAmountNotAllowed();
		}

		// Update pool-wise exchange rate of project tokens
		_tick();

		// Calc claimable amount
		uint256 cumExRate = cumulativeExchangeRate;
		uint256 claimableProjectTokenAmount = ((staker.nativeAmount *
			cumExRate) / SCALING_FACTOR) - staker.claimOffset;

		if (claimableProjectTokenAmount == 0) {
			revert ZeroAmountNotAllowed();
		}

		staker.claimOffset = (staker.nativeAmount * cumExRate) / SCALING_FACTOR;

		// Write staker back to storage
		stakers[stakerAddr] = staker;

		projectToken.safeTransfer(stakerAddr, claimableProjectTokenAmount);
		emit ProjectTokensClaimed(stakerAddr, claimableProjectTokenAmount);
	}

	function recoverWrongToken(
		address _tokenAddress
	) external onlyOwner notProjectToken(_tokenAddress) {
		IERC20 token = IERC20(_tokenAddress);
		uint256 balance = token.balanceOf(address(this));
		token.safeTransfer(owner(), balance);
	}

	/**
	 * @notice Allows the owner to withdraw any leftover project tokens after pool ends
	 * @dev Right now, we have no way to implement this function. Considering remove it completely
	 */
	function claimLeftoverProjectToken() external onlyOwner afterPoolEnd {}

	function claimOwnerInterest()
		external
		onlyOwner
		nonReentrant
		handleNativeExRateAfterEnd
	{
		(
			uint256 ownerClaims,
			uint256 platformFee
		) = getPlatformAndOwnerClaimableVAssets();
		address claimer = _msgSender();
		emit OwnerInterestsClaimed(claimer, ownerClaims, platformFee);
		acceptedVAsset.safeTransfer(claimer, ownerClaims);
		acceptedVAsset.safeTransfer(platformAdminAddress, platformFee);
	}

	function claimPlatformFee()
		external
		onlyPlatformAdmin
		afterPoolEnd
		nonReentrant
		handleNativeExRateAfterEnd
	{
		if (platformFeeClaimed) {
			revert PlatformFeeAlreadyClaimed();
		}

		// Enforce update of avg. native exrate gradient if it's 0
		// if (avgNativeExRateGradient == 0) {
		// 	uint256 vAssetAmount = ONE_VTOKEN;
		// 	uint256 nativeAmount = _getTokenByVTokenWithoutFee(vAssetAmount);
		// 	_updateNativeTokenExchangeRate(nativeAmount, vAssetAmount);
		// }

		// Always call this getter func b4 setting platformFeeClaimed to true
		(, uint256 platformFee) = getPlatformAndOwnerClaimableVAssets();
		platformFeeClaimed = true;

		emit PlatformFeeClaimed(_msgSender(), platformFee);
		acceptedVAsset.safeTransfer(platformAdminAddress, platformFee);
	}

	function setXCMOracleAddress(
		address _xcmOracleAddress
	) external onlyPlatformAdmin {
		xcmOracle = IXCMOracle(_xcmOracleAddress);
	}

	/**
	 * @dev This function is mostly used for front-end fetching
	 *  claimable project tokens on front-end
	 */
	function getClaimableProjectToken(
		address _investor
	) external view returns (uint256) {
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

	function getPoolInfo()
		external
		view
		returns (uint128, uint128, uint256, uint256)
	{
		return (
			startBlock,
			endBlock,
			getTotalProjectTokens(),
			getEmissionRate()
		);
	}

	function getPoolTokenomics() external view returns (PoolTokenomics memory) {
		return
			PoolTokenomics({
				totalNativeStake: totalNativeStake,
				totalVTokenStake: getTotalStakedVTokens(),
				projectTokenReserve: getTotalProjectTokens(),
				emissionRate: getEmissionRate(),
				projectTokenExchangeRate: cumulativeExchangeRate +
					_getPendingExchangeRate(),
				nativeTokenExchangeRate: lastNativeExRate
			});
	}

	function getPlatformAndOwnerClaimableVAssets()
		public
		view
		returns (uint256 ownerClaims, uint256 platformFee)
	{
		uint256 allVAssets = acceptedVAsset.balanceOf(address(this));

		if (allVAssets == 0) {
			return (0, 0);
		}

		uint256 investorVAssets = getWithdrawableVTokens(totalNativeStake);
		uint256 combinedClaims = allVAssets - investorVAssets;

		if (platformFeeClaimed) {
			return (combinedClaims, 0);
		}
		ownerClaims = (combinedClaims * ownerShareOfInterest) / 100;
		platformFee = combinedClaims - ownerClaims;
	}

	function getWithdrawableVTokens(
		uint256 _withdrawnNativeTokens
	) public view returns (uint256 withdrawableVAssets) {
		if (block.number <= endBlock) {
			withdrawableVAssets = _getVTokenByTokenWithoutFee(
				_withdrawnNativeTokens
			);
		} else {
			uint256 exRateAtEnd = _getEstimatedNativeExRateAtEnd();
			withdrawableVAssets =
				(_withdrawnNativeTokens * ONE_VTOKEN) /
				exRateAtEnd;
		}

		uint256 stakedVTokens = getTotalStakedVTokens();
		if (withdrawableVAssets > stakedVTokens) {
			withdrawableVAssets = stakedVTokens;
		}
	}

	function getTotalStakedVTokens() public view returns (uint256) {
		return acceptedVAsset.balanceOf(address(this));
	}

	function getTotalProjectTokens() public view returns (uint256) {
		return projectToken.balanceOf(address(this));
	}

	/**
	 * TODO: Need review
	 */
	function getStakingRange() public view returns (uint256, uint256) {
		return (maxTokenPerStaker, maxStakers);
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

	function getStakerNativeAmount(
		address _investor
	) public view returns (uint256) {
		return stakers[_investor].nativeAmount;
	}

	/**
	 * @notice For setting variables, injecting mock dependencies pre-constructor run, etc.
	 * @dev Plz override this
	 */
	function _preInit() internal virtual {}

	function _handleUnstakeAmount(
		Staker memory staker,
		uint256 _withdrawnVTokens
	) internal returns (uint256 withdrawnNativeTokens) {
		// Keep this as fail-fast mechanism to save gas
		if (staker.nativeAmount == 0) {
			revert ZeroAmountNotAllowed();
		}

		// Handle edge case: when the avg gradient is 0 after pool end
		// TODO: add test for this
		if (block.number > endBlock) {
			if (avgNativeExRateGradient == 0) {
				withdrawnNativeTokens = _getTokenByVTokenWithoutFee(
					_withdrawnVTokens
				);
				_updateNativeTokenExchangeRate(
					withdrawnNativeTokens,
					_withdrawnVTokens
				);
			} else {
				uint256 nativePerVToken = _getEstimatedNativeExRateAtEnd();
				withdrawnNativeTokens =
					(_withdrawnVTokens * nativePerVToken) /
					ONE_VTOKEN;
			}
		} else {
			withdrawnNativeTokens = _getTokenByVTokenWithoutFee(
				_withdrawnVTokens
			);
		}

		uint256 withdrawableVTokens = getWithdrawableVTokens(
			staker.nativeAmount
		);

		if (withdrawableVTokens < _withdrawnVTokens) {
			revert ExceedWithdrawableVTokens();
		}

		if (staker.nativeAmount < withdrawnNativeTokens) {
			revert ExceedNativeStake();
		}

		return (withdrawnNativeTokens);
	}

	function _tick() internal {
		uint256 currentBlock = block.number;
		if (currentBlock == tickBlock) {
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
		tickBlock = uint128(currentBlock);

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
		uint256 currentBlock = block.number;
		uint256 blockDelta = currentBlock - lastNativeExRateUpdateBlock;

		// Edge case: when multiple stakers stake at same block
		if (blockDelta == 0) {
			return;
		}

		// Edge case: after the pool ends, if the avg gradient is larger than zero, we stop here, else let it be updated
		// TODO: Add extensive invarianet tests for this edge case
		bool isAfterEndBlock = currentBlock > endBlock;
		bool isAvgGradientPositive = avgNativeExRateGradient > 0;
		if (isAfterEndBlock && isAvgGradientPositive) {
			return;
		}

		// Edge case: prevent case when the time gap between 2 stakers is too small, the rate delta is 0
		uint256 newNativeExRate = (_nativeAmount * ONE_VTOKEN) / _vTokenAmount;
		if (newNativeExRate <= lastNativeExRate) {
			return;
		}

		uint256 exRateDelta = newNativeExRate - lastNativeExRate;
		uint256 newGradientSample = exRateDelta / blockDelta;

		// Only update the last native exchange rate states if before end block
		if (!isAfterEndBlock) {
			lastNativeExRate = newNativeExRate;
			lastNativeExRateUpdateBlock = uint128(currentBlock);
		}

		// Calculate rolling average of the gradient
		avgNativeExRateGradient =
			(avgNativeExRateGradient *
				(nativeExRateSampleCount - 1) +
				newGradientSample) /
			(nativeExRateSampleCount);

		++nativeExRateSampleCount;
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

	/**
	 * @notice
	 * @dev This function should only be called after the pool end block, otherwise,
	 * there's risk of block.number - lastNativeExRateUpdateBlock = 0
	 */
	function _getEstimatedNativeExRateAtEnd()
		internal
		view
		returns (uint256 estimatedNativeExRateAtEnd)
	{
		uint256 blocksTilEnd = endBlock - lastNativeExRateUpdateBlock;
		// Handle edge case: when the gradient is 0 after pool end
		if (block.number > endBlock && avgNativeExRateGradient == 0) {
			uint256 newRate = _getTokenByVTokenWithoutFee(ONE_VTOKEN);
			// TODO: add test for this (it must not and cannot be 0)
			uint256 avgRateGradient = (newRate - lastNativeExRate) /
				(block.number - lastNativeExRateUpdateBlock);
			return
				lastNativeExRate +
				(avgRateGradient * (endBlock - lastNativeExRateUpdateBlock));
		}

		estimatedNativeExRateAtEnd =
			lastNativeExRate +
			(avgNativeExRateGradient * blocksTilEnd);
	}

	// TODO: add test for this
	function _getVTokenByTokenWithoutFee(
		uint256 _nativeAmount
	) internal view virtual returns (uint256 vAssetAmount) {
		bytes2 currencyId = xcmOracle.getCurrencyIdByAssetAddress(
			address(acceptedNativeAsset)
		);
		IXCMOracle.PoolInfo memory poolInfo = xcmOracle.tokenPool(currencyId);
		vAssetAmount =
			(_nativeAmount * poolInfo.vAssetAmount) /
			poolInfo.assetAmount;
	}

	// TODO: add test for this
	function _getTokenByVTokenWithoutFee(
		uint256 _vAssetAmount
	) internal view virtual returns (uint256 nativeAmount) {
		bytes2 currencyId = xcmOracle.getCurrencyIdByAssetAddress(
			address(acceptedNativeAsset)
		);
		IXCMOracle.PoolInfo memory poolInfo = xcmOracle.tokenPool(currencyId);

		nativeAmount =
			(_vAssetAmount * poolInfo.assetAmount) /
			poolInfo.vAssetAmount;
	}

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

	function _getTokenDecimals(
		address _tokenAddress
	) internal view returns (uint8) {
		try IERC20Metadata(_tokenAddress).decimals() returns (uint8 dec) {
			return dec;
		} catch {
			revert FailedToReadTokenDecimals();
		}
	}
}
