// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "@src/mocks/MockXCMOracle.sol";
import "@src/mocks/MockERC20.sol";

contract MockXCMOracleTest is Test {
	MockXCMOracle public oracle;
	address mockTokenAddress = address(0x1);

	// Default constructor parameters
	uint256 initialRate = 15;
	uint256 blockInterval = 50;
	uint256 incrementAmount = 1;

	function setUp() public {
		oracle = new MockXCMOracle(initialRate, blockInterval, incrementAmount);
	}

	function testInitialConfiguration() public {
		assertEq(oracle.baseExchangeRate(), initialRate);
		assertEq(oracle.blockInterval(), blockInterval);
		assertEq(oracle.incrementAmount(), incrementAmount);
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function testGetCurrentExchangeRate() public {
		assertEq(oracle.getCurrentExchangeRate(), initialRate);
		assertEq(oracle.getExchangeRate(), initialRate);
	}

	function testTokenConversion() public {
		uint256 amount = 1000;
		assertEq(
			oracle.getVTokenByToken(mockTokenAddress, amount),
			amount / initialRate
		);
		assertEq(
			oracle.getTokenByVToken(mockTokenAddress, amount),
			amount * initialRate
		);
	}

	function testSetExchangeRate() public {
		uint256 newRate = 20;
		oracle.setExchangeRate(newRate);
		assertEq(oracle.baseExchangeRate(), newRate);
		assertEq(oracle.getExchangeRate(), newRate);
	}

	function testSetBlockInterval() public {
		uint256 newInterval = 100;
		oracle.setBlockInterval(newInterval);
		assertEq(oracle.blockInterval(), newInterval);
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function testSetIncrementAmount() public {
		uint256 newIncrement = 2;
		oracle.setIncrementAmount(newIncrement);
		assertEq(oracle.incrementAmount(), newIncrement);
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function testSyncExchangeRate() public {
		oracle.syncExchangeRate();
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function testRateChangeAfterBlocks() public {
		// Warp forward by 50 blocks to trigger one increment
		vm.roll(block.number + 50);

		uint256 expectedRate = initialRate + incrementAmount;
		assertEq(oracle.getCurrentExchangeRate(), expectedRate);

		// Check token conversions with new rate
		uint256 amount = 1000;
		assertEq(
			oracle.getVTokenByToken(mockTokenAddress, amount),
			amount / expectedRate
		);
		assertEq(
			oracle.getTokenByVToken(mockTokenAddress, amount),
			amount * expectedRate
		);
	}

	function testMultipleBlockIntervals() public {
		// Warp forward by 105 blocks to trigger two increments
		vm.roll(block.number + 105);

		uint256 expectedRate = initialRate + (incrementAmount * 2);
		assertEq(oracle.getCurrentExchangeRate(), expectedRate);
	}

	function testRateUpdateAfterSetExchangeRate() public {
		// Advance some blocks to have a non-zero increment
		vm.roll(block.number + 60);
		// Check that rate has increased
		assertEq(
			oracle.getCurrentExchangeRate(),
			initialRate + incrementAmount
		);

		// Update the rate
		uint256 newRate = 25;
		oracle.setExchangeRate(newRate);

		// Verify that last block is updated
		assertEq(oracle.baseExchangeRate(), newRate);
		assertEq(oracle.lastUpdatedBlock(), block.number);

		// Move forward another block interval
		vm.roll(block.number + 50);

		// Check that the rate increases from the new base rate
		assertEq(oracle.getCurrentExchangeRate(), newRate + incrementAmount);
	}

	function testFuzzingRateChanges(uint8 blocks) public {
		vm.assume(blocks > 0);
		vm.roll(block.number + blocks);

		uint256 expectedIncrements = blocks / oracle.blockInterval();
		uint256 expectedRate = oracle.baseExchangeRate() +
			(expectedIncrements * oracle.incrementAmount());

		assertEq(oracle.getCurrentExchangeRate(), expectedRate);
	}

	function testFuzzingConversions(uint256 amount) public {
		vm.assume(amount > 0 && amount < type(uint256).max / initialRate);

		assertEq(
			oracle.getVTokenByToken(mockTokenAddress, amount),
			amount / initialRate
		);
		assertEq(
			oracle.getTokenByVToken(mockTokenAddress, amount),
			amount * initialRate
		);
	}
}
