// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";

/**
 * @title DeployLaunchpoolWithMocksScript
 * @notice A script to deploy a Launchpool with mock dependencies for testing purposes, due to testing native token is also reward token
 */
contract DeployLaunchpoolWithMocksScript is Script {
	function run() public {
		uint256 deployerPrivateKey = vm.envUint("PRIVATE_DEV_KEY");
		vm.startBroadcast(deployerPrivateKey);

		// Deploy Mock XCM Oracle
		// Parameters: initialRate (1:1), blockInterval (1), apy (5%), networkBlockTime (12 seconds)
		MockXCMOracle mockXCMOracle = new MockXCMOracle(
			1e18, // Initial 1:1 exchange rate
			1, // Update every block
			50_000, // 5% APY (with 6 decimals of precision)
			12 // 12 second block time
		);

		// Deploy Mock DOT and vDOT tokens
		MockERC20 dotToken = new MockERC20("Dot", "DOT");
		MockERC20 vDotToken = new MockERC20("Voucher Dot", "vDOT");

		// Set both tokens to have 12 decimals (matching DOT's decimals)
		dotToken.setDecimals(12);
		vDotToken.setDecimals(12);

		// Pre-mint some tokens to the deployer
		uint256 initialMint = 1_000_000 * 10 ** 12; // 1 million tokens
		dotToken.freeMint(initialMint);
		vDotToken.freeMint(initialMint);

		// Calculate blocks for the Launchpool duration
		uint128 currentBlock = uint128(block.number);
		uint128 startBlock = currentBlock + 100; // Start 100 blocks from now
		uint128 endBlock = startBlock + 50_000; // Run for 50,000 blocks (about 1 week at 12 sec blocks)

		// Prepare change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](3);
		uint256[] memory emissionRates = new uint256[](3);

		// Configure emission schedule
		changeBlocks[0] = startBlock; // Start with initial rate
		changeBlocks[1] = startBlock + 25_000; // Change halfway through
		changeBlocks[2] = endBlock - 10_000; // Change near the end

		emissionRates[0] = 10 * 10 ** 12; // 10 tokens per block initially
		emissionRates[1] = 5 * 10 ** 12; // 5 tokens per block in the middle
		emissionRates[2] = 2 * 10 ** 12; // 2 tokens per block at the end

		// Maximum tokens per staker (100,000 DOT)
		uint256 maxTokenPerStaker = 100_000 * 10 ** 12;

		// Deploy Launchpool
		Launchpool launchpool = new Launchpool(
			address(mockXCMOracle),
			msg.sender, // Project owner
			address(dotToken), // Project token is DOT
			address(vDotToken), // Accepted vAsset is vDOT
			address(dotToken), // Native asset is DOT
			startBlock,
			endBlock,
			maxTokenPerStaker,
			changeBlocks,
			emissionRates
		);

		// Mint DOT tokens to the Launchpool for rewards
		// Calculate total emission based on schedule
		uint256 totalEmission = emissionRates[0] *
			(changeBlocks[1] - changeBlocks[0]) +
			emissionRates[1] *
			(changeBlocks[2] - changeBlocks[1]) +
			emissionRates[2] *
			(endBlock - changeBlocks[2]);

		// Add a 10% buffer to ensure there are enough tokens
		uint256 tokensToMint = (totalEmission * 110) / 100;
		dotToken.freeMintTo(address(launchpool), tokensToMint);

		vm.stopBroadcast();

		// Log the deployed contract addresses
		console2.log("Deployed contracts:");
		console2.log("-------------------");
		console2.log("MockXCMOracle: ", address(mockXCMOracle));
		console2.log("DOT Token: ", address(dotToken));
		console2.log("vDOT Token: ", address(vDotToken));
		console2.log("Launchpool: ", address(launchpool));
		console2.log("-------------------");
		console2.log("Launchpool Configuration:");
		console2.log("Start Block: ", startBlock);
		console2.log("End Block: ", endBlock);
		console2.log("Total Emission: ~", totalEmission / 10 ** 12, " DOT");
		console2.log(
			"Max Token Per Staker: ",
			maxTokenPerStaker / 10 ** 12,
			" DOT"
		);
	}
}
