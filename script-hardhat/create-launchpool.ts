import { ethers } from "hardhat";

// Define the contract ABI
async function main(testParams: { proxyAddress: string }) {
	const [signer] = await ethers.getSigners();

	const contract = await ethers.getContractAt(
		"ProjectHubUpgradeable",
		testParams.proxyAddress,
		signer,
	);

	const createProjectTx = await contract.createProject();
	await createProjectTx.wait();
	console.log("Project Created!");

	const projectId = (await contract.nextProjectId()) - 1n;
	console.log("Our Project Id:", projectId);
	await new Promise((resolve) => setTimeout(resolve, 3000));

	// Use this before creating the launchpool
	const currentBlock = BigInt(await ethers.provider.getBlockNumber());
	console.log("Current Block:", currentBlock);
	const startBlock = currentBlock + 100n;
	const endBlock = startBlock + 1000n;
	const projectTokenAmount = ethers.toBigInt("1000000000000000000000000");

	// Approve project tokens for ProjectHub
	const projectTokenAddress = "0x9ca3B6f93D4ed8DdE19008cDff4261b7b44030E3";
	const vAssetAddress = "0xBc6137154f4EBf64Ee355e8774A7467B1d0CfF29";
	const projectToken = await ethers.getContractAt(
		"MockERC20",
		projectTokenAddress,
		signer,
	);
	await (await projectToken.freeMint(projectTokenAmount)).wait();
	// un-approve for testing rn
	await (
		await projectToken.approve(testParams.proxyAddress, projectTokenAmount)
	).wait();

	const params = {
		projectId: projectId,
		projectTokenAmount: projectTokenAmount,
		projectToken: projectTokenAddress, // Project Token
		vAsset: vAssetAddress, // Voucher Imagination
		startBlock: startBlock,
		endBlock: endBlock,
		maxVTokensPerStaker: ethers.toBigInt("1000000000000000000"),
		changeBlocks: [startBlock, startBlock + 100n],
		emissionRateChanges: [
			ethers.toBigInt("1000000000000000000"),
			ethers.toBigInt("500000000000000000"),
		],
		isListed: true,
	};

	// Send the transaction
	async function createLaunchpool() {
		const tx = await contract.createLaunchpool(params);
		console.log("Transaction Hash:", tx.hash);
		await tx.wait();
		console.log("Launchpool Created!");
	}

	createLaunchpool().catch(console.error);
}

main({
	proxyAddress: "0x863529d5AB4E62117214e89383dFE5AF039be84A",
}).catch(console.error);
