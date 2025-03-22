// SPDX-License-Identifier: SEE LICENSE IN LICENSE
/* solhint-disable */
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Decimal {
	function decimals() external view returns (uint8);
}

contract MockXCMOracle {
	struct PoolInfo {
		uint256 assetAmount;
		uint256 vAssetAmount;
	}

	// uint256 DECIMALS;
	// Real, hard-coded on-chain address of XCMOracle
	address public constant ORACLE_ONCHAIN_ADDRESS =
		0xEF81930Aa8ed07C17948B2E26b7bfAF20144eF2a;
	uint256 public exchangeRate;

	constructor() {
		// DECIMALS = 1;
		exchangeRate = 15;
	}

	function setExchangeRate(uint256 _exchangeRate) public {
		exchangeRate = _exchangeRate;
	}

	function tokenPool(
		bytes2 _currencyId
	) public view returns (PoolInfo memory) {
		return PoolInfo(15 ether, 10 ether);
	}

	function getCurrencyIdByAssetAddress(
		address _assetAddress
	) public view returns (bytes2) {
		return 0x0806;
	}

	function getVTokenByToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		//Takes in Native Asset address and Native amount then output the equivalent amount of vAsset
		//vAsset / nativeAsset > 0 =>vDOT is more valuable than DOT
		// uint256 decimal = IERC20Decimal(_assetAddress).decimals();
		// return (amount * 10 ** (decimal - 1)) / 15;
		return (amount * 10) / exchangeRate;
	}

	function getTokenByVToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		//Takes in Native Asset address and vAsset amount then output the equivalent amount of Native Asset
		// uint256 decimal = IERC20Decimal(_assetAddress).decimals();
		// return amount * 10 ** (decimal - 1) * 15;
		return (amount * exchangeRate) / 10;
	}

	function getExchangeRate() public view returns (uint256) {
		return exchangeRate;
	}
}
/* solhint-enable */
