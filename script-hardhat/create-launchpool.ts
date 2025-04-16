import { ethers } from "hardhat";

interface CreateLaunchpoolConfig {
	proxyAddress: string;
	vAssetAddress: string;
	nativeAssetAddress: string;
	projectTokenAddress: string;
}

async function main(config: CreateLaunchpoolConfig) {
	const [signer] = await ethers.getSigners();
	console.log("Using signer:", signer.address);

	const projectHubProxy = await ethers.getContractAt(
		"ProjectHubUpgradeable",
		config.proxyAddress,
		signer,
	);

	// Verify contract owner
	const owner = await projectHubProxy.owner();
	console.log("ProjectHub owner:", owner);
	console.log(
		"Is signer owner?",
		owner.toLowerCase() === signer.address.toLowerCase(),
	);

	// Verify XCM Oracle configuratio
	try {
		const xcmOracle = await projectHubProxy.xcmOracleAddress();
		console.log("XCM Oracle address:", xcmOracle);

		// Try to verify the XCM oracle works correctly by calling directly
		const mockXCMOracle = await ethers.getContractAt(
			"IXCMOracle",
			xcmOracle,
		);

		try {
			const currencyId = await mockXCMOracle.getCurrencyIdByAssetAddress(
				config.nativeAssetAddress,
			);
			console.log("Currency ID for native asset:", currencyId);

			const poolInfo = await mockXCMOracle.tokenPool(currencyId);
			console.log("Pool Info:", {
				assetAmount: poolInfo.assetAmount.toString(),
				vAssetAmount: poolInfo.vAssetAmount.toString(),
			});
		} catch (error) {
			console.error("Error accessing XCM Oracle functions:", error);
		}
	} catch (error) {
		console.error("Failed to verify XCM Oracle:", error);
	}

	// 1. Check if vAsset has a native asset mapping
	const nativeAsset = await projectHubProxy.vAssetToNativeAsset(
		config.vAssetAddress,
	);
	console.log("Mapped Native Asset:", nativeAsset);

	if (nativeAsset === "0x0000000000000000000000000000000000000000") {
		console.log("Setting up vAsset mapping first...");
		const setMappingTx = await projectHubProxy.setNativeAssetForVAsset(
			config.vAssetAddress,
			config.nativeAssetAddress,
		);
		await setMappingTx.wait();
		console.log("vAsset mapping created!");
	}

	// 2. Create project with dynamic ID tracking
	console.log("Creating new project...");
	const createProjectTx = await projectHubProxy.createProject();
	const receipt = await createProjectTx.wait();
	console.log("Project creation transaction hash:", createProjectTx.hash);

	// Look for project creation event
	const projectId = (await projectHubProxy.nextProjectId()) - 1n;
	console.log("Project Created with ID:", projectId);

	// Verify project ownership
	const project = await projectHubProxy.projects(projectId);
	console.log("Project owner:", project.projectOwner);
	console.log(
		"Is signer project owner?",
		project.projectOwner.toLowerCase() === signer.address.toLowerCase(),
	);

	// Get current block and set start/end blocks
	const currentBlock = BigInt(await ethers.provider.getBlockNumber());
	console.log("Current Block:", currentBlock);
	const startBlock = currentBlock + 10n;
	const endBlock = startBlock + 1000000000n;
	console.log("Start Block:", startBlock);
	console.log("End Block:", endBlock);

	// Approve project tokens
	const projectTokenAmount = ethers.toBigInt("1000000000000000000000000");
	const projectToken = await ethers.getContractAt(
		"MockERC20",
		config.projectTokenAddress,
		signer,
	);

	console.log("Checking project token balance and allowance...");
	const tokenBalance = await projectToken.balanceOf(signer.address);
	console.log("Project token balance:", tokenBalance.toString());

	if (tokenBalance < projectTokenAmount) {
		console.log("Minting project tokens...");
		await (await projectToken.freeMint(projectTokenAmount)).wait();
		console.log("Project tokens minted!");
	}

	const currentAllowance = await projectToken.allowance(
		signer.address,
		config.proxyAddress,
	);
	console.log("Current token allowance:", currentAllowance.toString());

	if (currentAllowance < projectTokenAmount) {
		console.log("Approving project tokens...");
		await (
			await projectToken.approve(config.proxyAddress, projectTokenAmount)
		).wait();
		console.log("Project tokens approved!");
	}

	const params = {
		projectId: projectId,
		projectTokenAmount: projectTokenAmount,
		projectToken: config.projectTokenAddress,
		vAsset: config.vAssetAddress,
		startBlock: startBlock,
		endBlock: endBlock,
		maxVTokensPerStaker: ethers.parseEther("10000"),
		changeBlocks: [startBlock, startBlock + 100n],
		emissionRateChanges: [
			ethers.toBigInt("1000000000000000000"),
			ethers.toBigInt("500000000000000000"),
		],
	};

	console.log("Creating launchpool with params:", {
		projectId: Number(params.projectId),
		startBlock: Number(params.startBlock),
		endBlock: Number(params.endBlock),
		vAsset: params.vAsset,
		changeBlocksCount: params.changeBlocks.length,
	});

	try {
		const estimatedGas =
			await projectHubProxy.createLaunchpool.estimateGas(params);
		console.log("Estimated gas:", estimatedGas.toString());

		const tx = await projectHubProxy.createLaunchpool(params, {
			gasLimit: (estimatedGas * 12n) / 10n, // Add 20% buffer
		});
		console.log("Transaction Hash:", tx.hash);
		await tx.wait();
		console.log("Launchpool Created!");

		// Get newly created launchpool details
		try {
			const poolId = (await projectHubProxy.nextPoolId()) - 1n;
			const pool = await projectHubProxy.pools(poolId);
			console.log("Created pool details:", {
				poolId: Number(pool.poolId),
				projectId: Number(pool.projectId),
				poolType: pool.poolType,
				poolAddress: pool.poolAddress,
			});
		} catch (error) {
			console.error("Error fetching pool details:", error);
		}
	} catch (error) {
		console.error("Failed to create launchpool:");

		if (error.error && error.error.data) {
			// For lower level revert reasons
			console.error("Error data:", error.error.data);
		}

		// Extract meaningful error message from revert
		if ((error as any).message) {
			console.error("Error message:", (error as any).message);

			if ((error as any).message.includes("reverted")) {
				const match = (error as any).message.match(
					/reverted with reason string '([^']+)'/,
				);
				if (match) {
					console.error("Revert reason:", match[1]);
				} else if (
					(error as any).message.includes(
						"reverted with custom error",
					)
				) {
					console.error("Reverted with custom error");
				} else if (
					(error as any).message.includes("reverted with panic code")
				) {
					const panicMatch = (error as any).message.match(
						/reverted with panic code 0x([0-9a-f]+)/,
					);
					if (panicMatch) {
						const panicCode = panicMatch[1];
						console.error(`Panic code: 0x${panicCode}`);
						// Interpret panic code
						const panicReasons: Record<string, string> = {
							"01": "Assert failed",
							"11": "Arithmetic overflow/underflow",
							"12": "Division by zero",
							"21": "Invalid enum value",
							"22": "Storage access out of bounds",
							"31": "Pop from empty array",
							"32": "Array index out of bounds",
							"41": "Memory overflow",
							"51": "Zero initialized variable",
						};
						console.error(
							`Panic reason: ${panicReasons[panicCode] || "Unknown panic code"}`,
						);
					}
				}
			}
		}

		// Try to find more specific information about why the transaction might have failed
		if ((error as any).transaction) {
			console.log(
				"Trying to simulate the failed transaction to get more details...",
			);
			try {
				const provider = ethers.provider;
				provider
					.call({
						to: (error as any).transaction.to,
						data: (error as any).transaction.data,
						from: (error as any).transaction.from,
					})
					.catch((callError) => {
						console.error("Simulated call error:", callError);
					});
			} catch (simulationError) {
				console.error(
					"Error during transaction simulation:",
					simulationError,
				);
			}
		}
	}
}

main({
	proxyAddress: "0xa6f8E8f5265b829515727B32A795963E1Efd7CF4",
	vAssetAddress: "0xD02D73E05b002Cb8EB7BEf9DF8Ed68ed39752465",
	nativeAssetAddress: "0x7a4ebae8cA815b9F52F23a8AC9A2f707D4d4ff81",
	projectTokenAddress: "0x96b6D28DF53641A47be72F44BE8C626bf07365A8",
}).catch(console.error);
