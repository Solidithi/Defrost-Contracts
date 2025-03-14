// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { MockXCMOracle } from "../../src/mocks/BetterMockXCMOracle.sol";
import "forge-std/Test.sol";

contract MockXCMOracleTest is Test {
	MockXCMOracle public oracle;
	address _mockTokenAddress = address(0x1);

	// Default constructor parameters
	uint256 _initialRate = 15;
	uint256 _blockInterval = 50;
	uint256 _increasementAmount = 1;

	function setUp() public {
		oracle = new MockXCMOracle(
			_initialRate,
			_blockInterval,
			_increasementAmount
		);
	}

	function test_initial_configuration() public {
		assertEq(oracle.baseExchangeRate(), _initialRate);
		assertEq(oracle.blockInterval(), _blockInterval);
		assertEq(oracle.increasementAmount(), _increasementAmount);
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function test_get_current_exchange_rate() public {
		assertEq(oracle.getCurrentExchangeRate(), _initialRate);
		assertEq(oracle.getExchangeRate(), _initialRate);
	}

	function test_token_conversion() public {
		uint256 amount = 1000;
		assertEq(
			oracle.getVTokenByToken(_mockTokenAddress, amount),
			amount / _initialRate
		);
		assertEq(
			oracle.getTokenByVToken(_mockTokenAddress, amount),
			amount * _initialRate
		);
	}

	function test_set_exchange_rate() public {
		uint256 newRate = 20;
		oracle.setExchangeRate(newRate);
		assertEq(oracle.baseExchangeRate(), newRate);
		assertEq(oracle.getExchangeRate(), newRate);
	}

	function test_set_block_interval() public {
		uint256 newInterval = 100;
		oracle.setBlockInterval(newInterval);
		assertEq(oracle.blockInterval(), newInterval);
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function test_set_increasement_amount() public {
		uint256 newIncrement = 2;
		oracle.setIncreasementAmount(newIncrement);
		assertEq(oracle.increasementAmount(), newIncrement);
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function test_sync_exchange_rate() public {
		oracle.syncExchangeRate();
		assertEq(oracle.lastUpdatedBlock(), block.number);
	}

	function test_rate_change_after_blocks() public {
		// Warp forward by 50 blocks to trigger one increment
		vm.roll(block.number + 50);

		uint256 expectedRate = _initialRate + _increasementAmount;
		assertEq(oracle.getCurrentExchangeRate(), expectedRate);

		// Check token conversions with new rate
		uint256 amount = 1000;
		assertEq(
			oracle.getVTokenByToken(_mockTokenAddress, amount),
			amount / expectedRate
		);
		assertEq(
			oracle.getTokenByVToken(_mockTokenAddress, amount),
			amount * expectedRate
		);
	}

	function test_multiple_block_intervals() public {
		// Warp forward by 105 blocks to trigger two increments
		vm.roll(block.number + 105);

		uint256 expectedRate = _initialRate + (_increasementAmount * 2);
		assertEq(oracle.getCurrentExchangeRate(), expectedRate);
	}

	function test_rate_update_after_set_exchange_rate() public {
		// Advance some blocks to have a non-zero increment
		vm.roll(block.number + 60);
		// Check that rate has increased
		assertEq(
			oracle.getCurrentExchangeRate(),
			_initialRate + _increasementAmount
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
		assertEq(
			oracle.getCurrentExchangeRate(),
			newRate + _increasementAmount
		);
	}

	function test_fuzzing_rate_changes(uint8 blocks) public {
		vm.assume(blocks > 0);
		vm.roll(block.number + blocks);

		uint256 expectedIncrements = blocks / oracle.blockInterval();
		uint256 expectedRate = oracle.baseExchangeRate() +
			(expectedIncrements * oracle.increasementAmount());

		assertEq(oracle.getCurrentExchangeRate(), expectedRate);
	}

	function test_fuzzing_conversions(uint256 amount) public {
		vm.assume(amount > 0 && amount < type(uint256).max / _initialRate);

		assertEq(
			oracle.getVTokenByToken(_mockTokenAddress, amount),
			amount / _initialRate
		);
		assertEq(
			oracle.getTokenByVToken(_mockTokenAddress, amount),
			amount * _initialRate
		);
	}
}
