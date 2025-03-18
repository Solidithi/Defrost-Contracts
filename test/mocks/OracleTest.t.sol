// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/mocks/MockXCMOracle.sol";
import "../../src/mocks/MockERC20.sol";

contract MockXCMOracleTest is Test {
	MockXCMOracle public oracle;
	MockERC20 public mockToken;

	// Default constructor parameters
	uint256 public initialRate = 12000; // 1.2 with 4 decimals
	uint256 public blockInterval = 10;
	uint256 public increasementAmount = 100; // 0.01 with 4 decimals
	uint8 public mintRate = 50; // 0.5% fee
	uint8 public redeemRate = 100; // 1% fee

	function setUp() public {
		oracle = new MockXCMOracle(
			initialRate,
			blockInterval,
			increasementAmount,
			mintRate,
			redeemRate
		);
		mockToken = new MockERC20("Test Token", "TEST");
	}

	function test_initialRatio() public {
		// Test that the initial ratio is 1:1.2
		uint256 vTokenAmount = 10000; // 1 vToken
		uint256 expectedNativeAmount = 12000; // 1.2 native tokens

		// Calculate native tokens from vTokens without fee
		uint256 nativeTokensBeforeFee = (vTokenAmount * initialRate) / 10000;
		assertEq(nativeTokensBeforeFee, expectedNativeAmount);

		// Calculate with fee
		uint256 redeemFee = (redeemRate * nativeTokensBeforeFee) / 10000;
		uint256 actualNativeAmount = nativeTokensBeforeFee - redeemFee;

		// 1.2 - (1.2 * 0.01) = 1.188 native tokens
		assertEq(actualNativeAmount, 11880);
		assertEq(
			oracle.getTokenByVToken(address(mockToken), vTokenAmount),
			actualNativeAmount
		);
	}

	function test_increasingRatio() public {
		// Test that the ratio increases correctly over blocks

		// Check initial ratio at block 0
		assertEq(oracle.getExchangeRate(), initialRate); // 1.2

		// Move to block 10 (one interval)
		vm.roll(block.number + blockInterval);
		assertEq(oracle.getExchangeRate(), initialRate + increasementAmount); // 1.21

		// Move to block 20 (another interval)
		vm.roll(block.number + blockInterval);
		assertEq(
			oracle.getExchangeRate(),
			initialRate + 2 * increasementAmount
		); // 1.22

		// Move to block 30 (another interval)
		vm.roll(block.number + blockInterval);
		assertEq(
			oracle.getExchangeRate(),
			initialRate + 3 * increasementAmount
		); // 1.23

		// At block 30, 1 vToken should be 1.5 native tokens before fee
		uint256 vTokenAmount = 10000; // 1 vToken
		uint256 currentRate = oracle.getExchangeRate();
		uint256 nativeTokensBeforeFee = (vTokenAmount * currentRate) / 10000;
		assertEq(nativeTokensBeforeFee, 12300); // 1.23 native tokens

		// With fee
		uint256 redeemFee = (redeemRate * nativeTokensBeforeFee) / 10000;
		uint256 actualNativeAmount = nativeTokensBeforeFee - redeemFee;

		// 1.23 - (1.23 * 0.01) = 1.2177 native tokens
		assertEq(actualNativeAmount, 12177);
		assertEq(
			oracle.getTokenByVToken(address(mockToken), vTokenAmount),
			actualNativeAmount
		);
	}

	function test_vTokenCalculationWithFee() public {
		// Test conversion from native tokens to vTokens with mint fee

		uint256 nativeAmount = 12000; // 1.2 native tokens

		// Calculate expected vTokens with fee
		uint256 mintFee = (mintRate * nativeAmount) / 10000; // 0.5% fee
		uint256 amountAfterFee = nativeAmount - mintFee;
		uint256 expectedVTokens = (amountAfterFee * 10000) / initialRate;

		// 1.2 - (1.2 * 0.005) = 1.194 native tokens
		// 1.194 / 1.2 = 0.995 vTokens
		assertEq(mintFee, 60); // 0.006 native tokens
		assertEq(amountAfterFee, 11940); // 1.194 native tokens
		assertEq(expectedVTokens, 9950); // 0.995 vTokens
		assertEq(
			oracle.getVTokenByToken(address(mockToken), nativeAmount),
			expectedVTokens
		);
	}

	function test_syncExchangeRate() public {
		// Move forward by 25 blocks (2.5 intervals)
		vm.roll(block.number + 25);

		// Check the current rate without synchronizing
		uint256 expectedRate = initialRate + (2 * increasementAmount); // 1.4
		assertEq(oracle.getExchangeRate(), expectedRate);

		// Synchronize the exchange rate
		oracle.syncExchangeRate();

		// Base rate should now be updated to the current rate
		assertEq(oracle.baseExchangeRate(), expectedRate);

		// Last updated block should be current block
		assertEq(oracle.lastUpdatedBlock(), block.number);

		// Moving forward another 5 blocks (0.5 intervals) should not change rate
		vm.roll(block.number + 5);
		assertEq(oracle.getExchangeRate(), expectedRate);

		// Moving forward another 5 blocks (completing an interval) should increase rate
		vm.roll(block.number + 5);
		assertEq(oracle.getExchangeRate(), expectedRate + increasementAmount); // 1.5
	}

	function test_conversionRoundTrip() public {
		// Test a round trip conversion (native -> vToken -> native) to check for precision loss

		uint256 initialNativeAmount = 10000; // 1 native token

		// Convert native to vTokens
		uint256 vTokenAmount = oracle.getVTokenByToken(
			address(mockToken),
			initialNativeAmount
		);

		// Convert vTokens back to native
		uint256 finalNativeAmount = oracle.getTokenByVToken(
			address(mockToken),
			vTokenAmount
		);

		// Due to fees and rounding, there will be some loss
		uint256 expectedLoss = initialNativeAmount - finalNativeAmount;

		// Calculate loss as percentage
		uint256 lossPercentage = (expectedLoss * 10000) / initialNativeAmount;

		// Verify loss is within acceptable range (expected to be around 1.5% due to 0.5% mint fee and 1% redeem fee)
		assertTrue(lossPercentage > 145 && lossPercentage < 155);
	}

	function test_largeBlockJumps() public {
		// Test behavior with very large block jumps

		// Jump 1,000 blocks (100 intervals)
		vm.roll(block.number + 1000);

		uint256 expectedRate = initialRate + (100 * increasementAmount); // 12000 + 10000 = 22000 (2.2)
		assertEq(oracle.getExchangeRate(), expectedRate);

		// Test conversion at this high rate
		uint256 vTokenAmount = 10000; // 1 vToken
		uint256 expectedNativeTokens = 21780; // 2.2 - (2.2 * 0.01) = 2.178
		assertEq(
			oracle.getTokenByVToken(address(mockToken), vTokenAmount),
			expectedNativeTokens
		);
	}

	function test_manualRateUpdate() public {
		// Test manually updating the exchange rate
		uint256 newRate = 20000; // 2.0

		oracle.setExchangeRate(newRate);
		assertEq(oracle.baseExchangeRate(), newRate);
		assertEq(oracle.getExchangeRate(), newRate);

		// Test conversion with new rate
		uint256 vTokenAmount = 10000; // 1 vToken
		uint256 expectedNativeTokens = 19800; // 2.0 - (2.0 * 0.01) = 1.98
		assertEq(
			oracle.getTokenByVToken(address(mockToken), vTokenAmount),
			expectedNativeTokens
		);
	}

	function test_setBlockInterval() public {
		// Test updating block interval
		vm.roll(block.number + 15); // Move 1.5 intervals

		// Current rate should be 1.3
		assertEq(oracle.getExchangeRate(), initialRate + increasementAmount);

		// Change block interval to 20
		oracle.setBlockInterval(20);

		// Base rate should be updated to current rate
		assertEq(oracle.baseExchangeRate(), initialRate + increasementAmount);

		// Last updated block should be current block
		assertEq(oracle.lastUpdatedBlock(), block.number);

		// Move forward 20 blocks
		vm.roll(block.number + 20);

		// Rate should increase by one increment
		assertEq(
			oracle.getExchangeRate(),
			initialRate + 2 * increasementAmount
		);
	}

	function test_setIncreasementAmount() public {
		// Test updating increment amount
		vm.roll(block.number + 10); // Move 1 interval

		// Current rate should be 1.3
		assertEq(oracle.getExchangeRate(), initialRate + increasementAmount);

		// Change increment amount to 200 (0.02)
		oracle.setIncreasementAmount(200);

		// Base rate should be updated to current rate
		assertEq(oracle.baseExchangeRate(), initialRate + increasementAmount);

		// Move forward 10 blocks
		vm.roll(block.number + 10);

		// Rate should increase by new increment
		assertEq(
			oracle.getExchangeRate(),
			initialRate + increasementAmount + 200
		);
	}

	function test_fuzzExchangeRates(uint64 blocks) public {
		// Bound blocks to avoid overflow
		vm.assume(blocks > 0 && blocks < 1000000);

		vm.roll(block.number + blocks);

		uint256 expectedIncrements = blocks / blockInterval;
		uint256 expectedRate = initialRate +
			(expectedIncrements * increasementAmount);

		assertEq(oracle.getExchangeRate(), expectedRate);
	}

	function test_fuzzConversions(uint128 amount) public {
		// Bound amount to avoid overflow and ensure it's not too small
		// Small amounts can cause issues due to division rounding to zero
		vm.assume(amount >= 100 && amount < 1000000 * 10 ** 18);

		// Test native -> vToken conversion
		uint256 vTokens = oracle.getVTokenByToken(address(mockToken), amount);
		assertTrue(vTokens > 0);

		// Test vToken -> native conversion
		uint256 nativeTokens = oracle.getTokenByVToken(
			address(mockToken),
			amount
		);
		assertTrue(nativeTokens > 0);
	}

	function test_differentTokenDecimals() public {
		// Test with a token that has different decimals
		mockToken.setDecimals(6); // Change to 6 decimals

		// The oracle calculations should be independent of token decimals
		uint256 vTokenAmount = 10000; // 1 vToken

		// Expected calculation: 1 vToken * 1.2 exchange rate = 1.2 tokens, minus 1% fee = 1.188 tokens
		uint256 expectedNativeTokens = 11880; // 1.188 with 4 decimals

		assertEq(
			oracle.getTokenByVToken(address(mockToken), vTokenAmount),
			expectedNativeTokens
		);
	}
}
