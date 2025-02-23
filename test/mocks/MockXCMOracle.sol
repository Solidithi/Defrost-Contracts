// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

contract MockXCMOracle {
	uint256 DECIMALS = 18;

	function getVTokenByToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		//Takes in Native Asset address and Native amount then output the equivalent amount of vAsset
		//vAsset / nativeAsset > 0 =>vDOT is more valuable than DOT

		return (amount * 10 ** (DECIMALS - 1)) / 15;
	}

	function getTokenByVToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		//Takes in Native Asset address and vAsset amount then output the equivalent amount of Native Asset
		return amount * 10 ** (DECIMALS - 1) * 15;
	}
}
