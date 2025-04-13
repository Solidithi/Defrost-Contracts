import { ethers } from "hardhat";

interface CreateLaunchpoolConfig {
	proxyAddress: string;
	vAssetAddress: string;
	nativeAssetAddress: string; // Add native asset address
	projectTokenAddress: string;
}

async function main(config: CreateLaunchpoolConfig) {
	const [signer] = await ethers.getSigners();
	const contract = await ethers.getContractAt(
		"ProjectHubUpgradeable",
		config.proxyAddress,
		signer,
	);

	// 1. Check if vAsset has a native asset mapping
	const nativeAsset = await contract.vAssetToNativeAsset(
		config.vAssetAddress,
	);
	console.log("Mapped Native Asset:", nativeAsset);

	if (nativeAsset === "0x0000000000000000000000000000000000000000") {
		console.log("Setting up vAsset mapping first...");
		const setMappingTx = await contract.setNativeAssetForVAsset(
			config.vAssetAddress,
			config.nativeAssetAddress,
		);
		await setMappingTx.wait();
		console.log("vAsset mapping created!");
	}

	// 2. Create project with dynamic ID tracking
	const createProjectTx = await contract.createProject();
	await createProjectTx.wait();
	const projectId = (await contract.nextProjectId()) - 1n;
	console.log("Project Created with ID:", projectId);

	// Get current block and set start/end blocks
	const currentBlock = BigInt(await ethers.provider.getBlockNumber());
	console.log("Current Block:", currentBlock);
	const startBlock = currentBlock + 1000n;
	const endBlock = startBlock + 1000n;

	// Approve project tokens
	const projectTokenAmount = ethers.toBigInt("1000000000000000000000000");
	const projectToken = await ethers.getContractAt(
		"MockERC20",
		config.projectTokenAddress,
		signer,
	);
	await (await projectToken.freeMint(projectTokenAmount)).wait();
	await (
		await projectToken.approve(config.proxyAddress, projectTokenAmount)
	).wait();

	const params = {
		projectId: projectId,
		projectTokenAmount: projectTokenAmount,
		projectToken: config.projectTokenAddress,
		vAsset: config.vAssetAddress,
		startBlock: startBlock,
		endBlock: endBlock,
		maxVTokensPerStaker: ethers.toBigInt("1000000000000000000"),
		changeBlocks: [startBlock, startBlock + 100n],
		emissionRateChanges: [
			ethers.toBigInt("1000000000000000000"),
			ethers.toBigInt("500000000000000000"),
		],
	};

	try {
		const tx = await contract.createLaunchpool(params);
		console.log("Transaction Hash:", tx.hash);
		await tx.wait();
		console.log("Launchpool Created!");
	} catch (error) {
		console.error("Failed to create launchpool:");
		console.error(error);

		// Extract meaningful error message from revert
		if (
			(error as any).message &&
			(error as any).message.includes("reverted")
		) {
			const match = (error as any).message.match(
				/reverted with reason string '([^']+)'/,
			);
			if (match) {
				console.error("Revert reason:", match[1]);
			}
		}
	}
}

main({
	proxyAddress: "0x42aADFe321D6d383b1355C6B9EA47D13D2B98dF7",
	vAssetAddress: "0xD02D73E05b002Cb8EB7BEf9DF8Ed68ed39752465",
	nativeAssetAddress: "0x7a4ebae8cA815b9F52F23a8AC9A2f707D4d4ff81",
	projectTokenAddress: "0x96b6D28DF53641A47be72F44BE8C626bf07365A8",
}).catch(console.error);
