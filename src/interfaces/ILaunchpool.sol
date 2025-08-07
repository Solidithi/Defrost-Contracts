// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface ILaunchpool {
	// Structs
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

	// Events
	event Staked(address indexed user, uint256 amount);
	event Unstaked(address indexed user, uint256 amount);
	event ProjectTokensClaimed(address indexed user, uint256 amount);
	event OwnerInterestsClaimed(
		address indexed claimer,
		uint256 ownerClaims,
		uint256 platformFee
	);
	event PlatformFeeClaimed(address indexed claimer, uint256 platformFee);

	// Functions
	function pause() external;

	function unpause() external;

	function stake(uint256 _vTokenAmount) external;

	function unstake(uint256 _vTokenAmount) external;

	function unstakeWithoutProjectToken(uint256 _withdrawnVTokens) external;

	function claimProjectTokens() external;

	function recoverWrongToken(address _tokenAddress) external;

	function claimLeftoverProjectToken() external;

	function claimOwnerInterest() external;

	function claimPlatformFee() external;

	function setXCMOracleAddress(address _xcmOracleAddress) external;

	// View Functions
	function owner() external view returns (address);

	function getClaimableProjectToken(
		address _investor
	) external view returns (uint256);

	function getPoolInfo()
		external
		view
		returns (uint128, uint128, uint256, uint256);

	function getPoolTokenomics() external view returns (PoolTokenomics memory);

	function getPlatformAndOwnerClaimableVAssets()
		external
		view
		returns (uint256 ownerClaims, uint256 platformFee);

	function getWithdrawableVTokens(
		uint256 _withdrawnNativeTokens
	) external view returns (uint256 withdrawableVAssets);

	function getTotalStakedVTokens() external view returns (uint256);

	function getTotalProjectTokens() external view returns (uint256);

	function getStakingRange() external view returns (uint256, uint256);

	function getEmissionRate() external view returns (uint256);

	function getStakerNativeAmount(
		address _investor
	) external view returns (uint256);

	// State Variables
	function cumulativeExchangeRate() external view returns (uint256);

	function startBlock() external view returns (uint128);

	function endBlock() external view returns (uint128);

	function tickBlock() external view returns (uint128);

	function ownerShareOfInterest() external view returns (uint128);

	function maxTokenPerStaker() external view returns (uint256);

	function maxStakers() external view returns (uint256);

	function SCALING_FACTOR() external view returns (uint256);

	function lastProcessedChangeBlockIndex() external view returns (uint256);

	function platformAdminAddress() external view returns (address);

	function changeBlocks(uint256 index) external view returns (uint128);

	function emissionRateChanges(
		uint128 blockNumber
	) external view returns (uint256);

	function projectToken() external view returns (address);

	function acceptedVAsset() external view returns (address);

	function acceptedNativeAsset() external view returns (address);

	function xcmOracle() external view returns (address);

	function stakers(address user) external view returns (Staker memory);

	function lastNativeExRate() external view returns (uint256);

	function avgNativeExRateGradient() external view returns (uint256);

	function nativeExRateSampleCount() external view returns (uint128);

	function lastNativeExRateUpdateBlock() external view returns (uint128);

	function ONE_VTOKEN() external view returns (uint256);

	function platformFeeClaimed() external view returns (bool);
}
