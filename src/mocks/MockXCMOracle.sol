// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Decimal {
	function decimals() external view returns (uint8);
}

contract MockXCMOracle {
	uint256 public baseExchangeRate;
	uint256 public blockInterval;
	uint256 public lastUpdatedBlock;
	uint256 public incrementAmount;

	constructor(
		uint256 _initialRate,
		uint256 _blockInterval,
		uint256 _incrementAmount
	) {
		baseExchangeRate = _initialRate;
		blockInterval = _blockInterval;
		incrementAmount = _incrementAmount;
		lastUpdatedBlock = block.number;
	}

	function setExchangeRate(uint256 _exchangeRate) public {
		baseExchangeRate = _exchangeRate;
		lastUpdatedBlock = block.number;
	}

	function setBlockInterval(uint256 _blockInterval) public {
		baseExchangeRate = getCurrentExchangeRate();
		lastUpdatedBlock = block.number;
		blockInterval = _blockInterval;
	}

	function setIncrementAmount(uint256 _incrementAmount) public {
		baseExchangeRate = getCurrentExchangeRate();
		lastUpdatedBlock = block.number;
		incrementAmount = _incrementAmount;
	}

	function syncExchangeRate() public {
		baseExchangeRate = getCurrentExchangeRate();
		lastUpdatedBlock = block.number;
	}

	function getCurrentExchangeRate() public view returns (uint256) {
		uint256 blocksPassed = block.number - lastUpdatedBlock;
		uint256 increments = blocksPassed / blockInterval;
		return baseExchangeRate + (increments * incrementAmount);
	}

	function getVTokenByToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		return amount / getCurrentExchangeRate();
	}

	function getTokenByVToken(
		address _assetAddress,
		uint256 amount
	) public view returns (uint256) {
		return amount * getCurrentExchangeRate();
	}

	function getExchangeRate() public view returns (uint256) {
		return getCurrentExchangeRate();
	}
}
