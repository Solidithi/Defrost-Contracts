// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface ILaunchpool {
	// Structs
	struct Staker {
		uint256 vAssetAmount;
		uint256 nativeTokenAmount;
		uint256 claimOffset;
	}

	// Events
	event Staked(address indexed user, uint256 amount);
	event Unstaked(address indexed user, uint256 amount);

	// Functions
	function stake(uint256 _amount) external;

	function unstake(uint256 _amount) external;

	function unstakeWithoutProjectToken() external;

	function recoverWrongToken(address _tokenAddress) external;

	function claimLeftoverProjectToken() external;

	function claimOwnerInterest() external;

	function claimPlatformInterest() external;

	function setXCMOracleAddress(address _xcmOracleAddress) external;

	// View Functions
	function owner() external view returns (address);

	function getPoolInfo()
		external
		view
		returns (uint128, uint128, uint256, uint256); // startBlock, endBlock, totalProjectToken, emissionRate

	function getTotalStaked() external view returns (uint256);

	function getTotalProjectToken() external view returns (uint256);

	function getStakingRange() external view returns (uint256, uint256); // maxVAssetPerStaker, maxStakers

	function getEmissionRate() external view returns (uint256);

	function getClaimableProjectToken(
		address _investor
	) external view returns (uint256);

	function getPlatformAndOwnerClaimableVAssets()
		external
		view
		returns (uint256 ownerClaims, uint256 platformFee);

	// State Variables
	function cumulativeExchangeRate() external view returns (uint256);

	function startBlock() external view returns (uint128);

	function endBlock() external view returns (uint128);

	function tickBlock() external view returns (uint128);

	function ownerShareOfInterest() external view returns (uint128);

	function maxVAssetPerStaker() external view returns (uint256);

	function maxStakers() external view returns (uint256);

	// solhint-disable-next-line
	function SCALING_FACTOR() external view returns (uint256);

	function lastProcessedChangeBlockIndex() external view returns (uint256);

	function platformAdminAddress() external view returns (address);

	function changeBlocks(uint256 index) external view returns (uint128);

	function emissionRateChanges(
		uint128 blockNumber
	) external view returns (uint256);

	function projectToken() external view returns (address);

	function acceptedVAsset() external view returns (address);

	function xcmOracle() external view returns (address);

	function stakers(address user) external view returns (Staker memory);
}
