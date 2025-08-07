import { ethers } from "hardhat";
import * as readline from "readline";

interface UnstakeLaunchpoolConfig {
	launchpoolAddress: string;
	vAssetAddress: string;
	amountToUnstake?: string; // Optional - if not provided, will prompt user
}

async function main(config?: UnstakeLaunchpoolConfig) {
	console.log("Unstaking vTokens from a Launchpool...");

	// Get signer
	const signers = await ethers.getSigners();
	const signer = signers[0];
	console.log("Using signer address:", signer.address);

	// If no config is provided, try to get from command line arguments
	if (!config) {
		const args = process.argv.slice(2);
		if (args.length < 2) {
			console.error(
				"Please provide launchpool address and vAsset address as command line arguments, e.g.:",
			);
			console.error(
				"npx hardhat run script-hardhat/unstake-launchpool.ts --network moonbase 0x123... 0x456... [amount]",
			);
			process.exit(1);
		}

		config = {
			launchpoolAddress: args[0],
			vAssetAddress: args[1],
			amountToUnstake: args[2], // Optional third argument
		};
	}

	console.log("Unstaking Configuration:");
	console.log("  Launchpool Address:", config.launchpoolAddress);
	console.log("  vAsset Address:", config.vAssetAddress);

	// Get contract instances
	const launchpool = await ethers.getContractAt(
		"Launchpool",
		config.launchpoolAddress,
		signer,
	);

	const vAsset = await ethers.getContractAt(
		"IERC20",
		config.vAssetAddress,
		signer,
	);

	// Get current staker information
	const stakerInfo = await launchpool.stakers(signer.address);
	console.log("\nCurrent Staker Information:");
	console.log(
		"  Native Amount Staked:",
		ethers.formatEther(stakerInfo.nativeAmount.toString()),
	);
	console.log(
		"  Claim Offset:",
		ethers.formatEther(stakerInfo.claimOffset.toString()),
	);

	if (stakerInfo.nativeAmount === 0n) {
		console.log("You have no stake in this launchpool.");
		process.exit(0);
	}

	// Get withdrawable vTokens
	const withdrawableVTokens = await launchpool.getWithdrawableVTokens(
		stakerInfo.nativeAmount,
	);
	console.log(
		"  Maximum Withdrawable vTokens:",
		ethers.formatEther(withdrawableVTokens.toString()),
	);

	if (withdrawableVTokens === 0n) {
		console.log("You have no withdrawable vTokens at this time.");
		process.exit(0);
	}

	// Get claimable project tokens
	const claimable = await launchpool.getClaimableProjectToken(signer.address);
	console.log(
		"  Claimable Project Tokens:",
		ethers.formatEther(claimable.toString()),
	);

	// Get launchpool information
	try {
		const poolInfo = await launchpool.getPoolInfo();
		console.log("\nPool Information:");
		console.log("  Start block:", poolInfo[0]);
		console.log("  End block:", poolInfo[1]);
		console.log(
			"  Total project tokens:",
			ethers.formatEther(poolInfo[2].toString()),
		);
		console.log(
			"  Emission rate:",
			ethers.formatEther(poolInfo[3].toString()),
		);

		// Check current block
		const currentBlock = await ethers.provider.getBlockNumber();
		console.log("  Current block:", currentBlock);
	} catch (error) {
		console.error("Error fetching pool information:", error);
		process.exit(1);
	}

	let amountToUnstake: bigint;

	// If amount is not provided in config, prompt user for input
	if (!config.amountToUnstake) {
		const rl = readline.createInterface({
			input: process.stdin,
			output: process.stdout,
		});

		const answer = await new Promise<string>((resolve) => {
			rl.question(
				`\nHow many vTokens would you like to unstake? (Max: ${ethers.formatEther(
					withdrawableVTokens,
				)}): `,
				(answer) => {
					rl.close();
					resolve(answer);
				},
			);
		});

		try {
			amountToUnstake = ethers.parseEther(answer.trim());
		} catch (error) {
			console.error(
				"Invalid amount format. Please enter a valid number.",
			);
			process.exit(1);
		}
	} else {
		amountToUnstake = ethers.toBigInt(config.amountToUnstake);
	}

	// Validate the amount
	if (amountToUnstake <= 0n) {
		console.error("Amount must be greater than 0.");
		process.exit(1);
	}

	if (amountToUnstake > withdrawableVTokens) {
		console.error(
			`Amount to unstake (${ethers.formatEther(
				amountToUnstake,
			)}) exceeds maximum withdrawable amount (${ethers.formatEther(
				withdrawableVTokens,
			)}).`,
		);
		process.exit(1);
	}

	console.log(
		`\nUnstaking ${ethers.formatEther(amountToUnstake)} vTokens...`,
	);

	// Get current vAsset balance before unstaking
	const vAssetBalanceBefore = await vAsset.balanceOf(signer.address);
	console.log(
		"Current vAsset balance:",
		ethers.formatEther(vAssetBalanceBefore.toString()),
	);

	// Unstake vTokens
	try {
		const unstakeTx = await launchpool.unstake(amountToUnstake);
		console.log("Transaction submitted. Waiting for confirmation...");
		await unstakeTx.wait();
		console.log("Unstaking successful!");

		// Get updated staker information
		const updatedStakerInfo = await launchpool.stakers(signer.address);
		console.log("\nUpdated Staker Information:");
		console.log(
			"  Native Amount Staked:",
			ethers.formatEther(updatedStakerInfo.nativeAmount.toString()),
		);
		console.log(
			"  Claim Offset:",
			ethers.formatEther(updatedStakerInfo.claimOffset.toString()),
		);

		// Get updated claimable project tokens
		const updatedClaimable = await launchpool.getClaimableProjectToken(
			signer.address,
		);
		console.log(
			"  Updated Claimable Project Tokens:",
			ethers.formatEther(updatedClaimable.toString()),
		);

		// Get updated vAsset balance
		const vAssetBalanceAfter = await vAsset.balanceOf(signer.address);
		console.log(
			"Updated vAsset balance:",
			ethers.formatEther(vAssetBalanceAfter.toString()),
		);

		const receivedVTokens = vAssetBalanceAfter - vAssetBalanceBefore;
		console.log(
			"vTokens received:",
			ethers.formatEther(receivedVTokens.toString()),
		);

		// Check if there are remaining withdrawable vTokens
		if (updatedStakerInfo.nativeAmount > 0n) {
			const remainingWithdrawable =
				await launchpool.getWithdrawableVTokens(
					updatedStakerInfo.nativeAmount,
				);
			console.log(
				"Remaining withdrawable vTokens:",
				ethers.formatEther(remainingWithdrawable.toString()),
			);
		}
	} catch (error) {
		console.error("Error unstaking vTokens:", error);
		console.log("Error details:", error);
		process.exit(1);
	}
}

// This handles running the script directly or being imported by another module
if (require.main === module) {
	main({
		// launchpoolAddress: "0xfbe66a07021d7cf5bd89486abe9690421dcc649b",
		launchpoolAddress: "0x206447b1d13ede7dd361f46725efcc1076dc884d",
		vAssetAddress: "0xD02D73E05b002Cb8EB7BEf9DF8Ed68ed39752465",
		// amountToUnstake: ethers.parseUnits("100", 18).toString(), // Uncomment to skip interactive input
	})
		.then(() => process.exit(0))
		.catch((error) => {
			console.error(error);
			process.exit(1);
		});
} else {
	module.exports = main;
}
