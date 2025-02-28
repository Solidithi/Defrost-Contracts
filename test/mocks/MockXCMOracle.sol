// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Decimal {
	function decimals() external view returns (uint8);
}

contract MockXCMOracle {
	// uint256 DECIMALS;
	uint256 EXCHANGE_RATE;

	constructor() {
		// DECIMALS = 1;
		EXCHANGE_RATE = 15;
		
	}

	function getVTokenByToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		//Takes in Native Asset address and Native amount then output the equivalent amount of vAsset
		//vAsset / nativeAsset > 0 =>vDOT is more valuable than DOT
		// uint256 decimal = IERC20Decimal(_assetAddress).decimals();
		// return (amount * 10 ** (decimal - 1)) / 15;
		return amount / EXCHANGE_RATE;
	}

	function getTokenByVToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		//Takes in Native Asset address and vAsset amount then output the equivalent amount of Native Asset
		// uint256 decimal = IERC20Decimal(_assetAddress).decimals();
		// return amount * 10 ** (decimal - 1) * 15;
		return amount * EXCHANGE_RATE;
	}

	function getExchangeRate() public view returns (uint256) {
		return EXCHANGE_RATE;
	}
	function setExchangeRate(uint256 _exchangeRate) public {
		EXCHANGE_RATE = _exchangeRate;
	}
}
