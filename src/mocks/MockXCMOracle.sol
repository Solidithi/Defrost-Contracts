// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Decimal {
	function decimals() external view returns (uint8);
}

contract MockXCMOracle {
	struct RateInfo {
		uint8 mintRate; // Minting fee rate in basis points (bps)
		uint8 redeemRate; // Redemption fee rate in basis points (bps)
	}

	uint256 public baseExchangeRate;
	uint256 public blockInterval;
	uint256 public lastUpdatedBlock;
	uint256 public increasementAmount;
	uint256 public immutable DECIMALS = 4; // 4 decimal precision

	RateInfo public rateInfo;

	constructor(
		uint256 _initialRate, // Initial exchange rate (without decimals), make sure this value is pre-multiply by 10^DECIMALS
		uint256 _blockInterval, // Block interval for rate increments
		uint256 _increasementAmount, // Amount to increase exchange rate per interval
		uint8 _mintRate, // Minting fee rate in bps
		uint8 _redeemRate // Redemption fee rate in bps
	) {
		baseExchangeRate = _initialRate; // Adjust for precision
		blockInterval = _blockInterval;
		increasementAmount = _increasementAmount;
		lastUpdatedBlock = block.number;
		rateInfo = RateInfo(_mintRate, _redeemRate);
	}

	/**
	 * @dev Updates the exchange rate manually.
	 */
	function setExchangeRate(uint256 _exchangeRate) public {
		baseExchangeRate = _exchangeRate;
		lastUpdatedBlock = block.number;
	}

	/**
	 * @dev Updates the block interval and syncs the exchange rate.
	 */
	function setBlockInterval(uint256 _blockInterval) public {
		baseExchangeRate = getCurrentExchangeRate();
		lastUpdatedBlock = block.number;
		blockInterval = _blockInterval;
	}

	/**
	 * @dev Updates the increment amount and syncs the exchange rate.
	 */
	function setIncreasementAmount(uint256 _increasementAmount) public {
		baseExchangeRate = getCurrentExchangeRate();
		lastUpdatedBlock = block.number;
		increasementAmount = _increasementAmount;
	}

	/**
	 * @dev Syncs the current exchange rate based on time elapsed.
	 */
	function syncExchangeRate() public {
		baseExchangeRate = getCurrentExchangeRate();
		lastUpdatedBlock = block.number;
	}

	/**
	 * @dev Returns the current exchange rate, accounting for time-based increments.
	 */
	function getCurrentExchangeRate() public view returns (uint256) {
		uint256 blocksPassed = block.number - lastUpdatedBlock;
		uint256 increments = blocksPassed / blockInterval;
		return baseExchangeRate + (increments * increasementAmount);
	}

	/**
	 * @dev Converts tokens to vTokens, applying mint fee.
	 * Formula: vTokens = (tokens - mintFee) * (10^DECIMALS / exchangeRate)
	 */
	function getVTokenByToken(
		address assetAddress,
		uint256 amount
	) public view returns (uint256) {
		uint256 mintFee = (rateInfo.mintRate * amount) / 10000;
		uint256 assetAmountExcludingFee = amount - mintFee; // Deduct fee
		return
			(assetAmountExcludingFee * 10 ** DECIMALS) /
			getCurrentExchangeRate();
	}

	/**
	 * @dev Converts vTokens to tokens, applying redeem fee.
	 * Formula: tokens = (vTokens * exchangeRate) / 10^DECIMALS - redeemFee
	 */
	function getTokenByVToken(
		address assetAddress,
		uint256 amount
	) public view returns (uint256) {
		uint256 assetAmount = (amount * getCurrentExchangeRate()) /
			10 ** DECIMALS; // Convert vTokens to asset
		uint256 redeemFee = (rateInfo.redeemRate * assetAmount) / 10000;
		return assetAmount - redeemFee;
	}

	/**
	 * @dev Returns the latest exchange rate.
	 */
	function getExchangeRate() public view returns (uint256) {
		return getCurrentExchangeRate();
	}
}
