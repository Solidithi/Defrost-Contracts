// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity ^0.8.26;
import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Decimal {
	function decimals() external view returns (uint8);
}

contract MockXCMOracle {
	struct PoolInfo {
		uint256 nativeAmount;
		uint256 vAssetAmount;
	}

	PoolInfo public poolInfo = PoolInfo(1, 1);

	uint256 public baseExchangeRate;
	uint256 public blockInterval;
	uint256 public lastUpdatedBlock;
	uint256 public nativeIncrementPerInterval;
	uint256 public exchangeRate;

	uint256 public immutable NETWORK_BLOCK_TIME;
	uint256 public constant APY_DECIMALS = 6;
	uint256 public constant RATE_DECIMALS = 4;

	/**
	 *
	 * @param _initialRate initial exchange rate, 4-decimal precision, e.g. 1.2 => 12.000, 1.5 => 15.000
	 * @param _blockInterval block interval for exchange rate update (how many blocks in an interval)
	 * @param _apy APY in percentage, 6-decimal precision, e.g. 0.01 => 10.000, 0.5034 => 503.400
	 * @param _networkBlockTime block time in seconds, e.g 12 secs for Ethereum, 6 secs for Moonbeam
	 */
	constructor(
		uint256 _initialRate,
		uint256 _blockInterval,
		uint256 _apy,
		uint256 _networkBlockTime
	) {
		if (_networkBlockTime == 0) {
			revert(
				"Dawg, u tryna pull a division-by-0 stunt? _networkBlockTime must be ge. 1"
			);
		}

		if (_blockInterval == 0) {
			revert(
				"Dawg, u tryna pull a division-by-0 stunt? _blockInterval must be ge. 1"
			);
		}

		blockInterval = _blockInterval;
		NETWORK_BLOCK_TIME = _networkBlockTime;

		setExchangeRate(_initialRate);
		setAPY(_apy);
	}

	/**
	 *
	 * @notice Set native increment per interval (a more direct alternative to setAPY)
	 * @param _nativeIncrementPerInterval native increment per interval
	 */
	function setNativeIncrementPerInterval(
		uint256 _nativeIncrementPerInterval
	) public {
		syncExchangeRate();
		nativeIncrementPerInterval = _nativeIncrementPerInterval;
	}

	/**
	 *
	 * @notice Set APY for the oracle, which will be used to derive native increment per interval
	 * @param _apy APY in percentage, 6-decimal precision, e.g. 0.01 => 10.000, 0.5034 => 503.400
	 * @param _apy will be used to derive native increment per interval
	 */
	function setAPY(uint256 _apy) public {
		// Derive native increment amount from APY
		uint256 annualNativeIncrement = (_apy * poolInfo.nativeAmount) /
			(10 ** APY_DECIMALS);
		uint256 nativeIncrementPerBlock = annualNativeIncrement /
			(365 days / NETWORK_BLOCK_TIME);
		setNativeIncrementPerInterval(nativeIncrementPerBlock * blockInterval);
	}

	/**
	 *
	 * @notice Set custom exchange rate for the oracle
	 * @param _exchangeRate exchange rate to set
	 */
	function setExchangeRate(uint256 _exchangeRate) public {
		poolInfo.nativeAmount *= _exchangeRate / (10 ** RATE_DECIMALS);
		baseExchangeRate = _exchangeRate;
		lastUpdatedBlock = block.number;
	}

	/**
	 *
	 * @notice Decide the number of blocks per interval for exchange rate update
	 * @param _blockInterval block interval for exchange rate update (how many blocks in an interval)
	 */
	function setBlockInterval(uint256 _blockInterval) public {
		lastUpdatedBlock = block.number;
		blockInterval = _blockInterval;
	}

	/**
	 *
	 * @notice Re-estimate exchange rate based on the current block number
	 */
	function syncExchangeRate() public {
		uint256 newestRate = getCurrentExchangeRate();
		setExchangeRate(newestRate);
	}

	function getCurrentExchangeRate() public view returns (uint256) {
		uint256 blocksPassed = block.number - lastUpdatedBlock;
		uint256 intervals = blocksPassed / blockInterval;
		uint256 currentNativeAmt = poolInfo.nativeAmount +
			(intervals * nativeIncrementPerInterval);
		return
			(currentNativeAmt * (10 ** RATE_DECIMALS)) / poolInfo.vAssetAmount;
	}

	/**
	 *
	 * @notice Mock return same token pool for all currency
	 * @param _currencyId Currency ID
	 */
	function tokenPool(
		bytes2 _currencyId
	) public view returns (PoolInfo memory) {
		return poolInfo;
	}

	/**
	 *
	 * @notice Mock return same token pool for all native address
	 * @param _nativeAddress native asset address
	 */
	function getCurrencyIdByAssetAddress(
		address _nativeAddress
	) public view returns (bytes2) {
		return 0x0806;
	}

	/**
	 * @notice No more needed, we raw-dogging conversionss
	 * between vAsset and native in Launchpool.sol
	 *
	 **/
	// function getVTokenByToken(
	// 	address _assetAddress,
	// 	uint256 amount
	// ) public view returns (uint256) {
	// 	return amount / getCurrentExchangeRate();
	// }

	// function getTokenByVToken(
	// 	address _assetAddress,
	// 	uint256 amount
	// ) public view returns (uint256) {
	// 	return amount * getCurrentExchangeRate();
	// }
}
/* solhint-enable*/
