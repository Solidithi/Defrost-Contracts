// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

interface IXCMOracle {
	// _assetAddress: Asset address, e.g. DOT, KSM
	// _assetAmount: Input asset amount, get vAsset amount
	// _vAssetAmount: Input vAsset amount, get asset amount
	function getVTokenByToken(
		address _assetAddress,
		uint256 _assetAmount
	) external view returns (uint256);

	function getTokenByVToken(
		address _assetAddress,
		uint256 _vAssetAmount
	) external view returns (uint256);
}
