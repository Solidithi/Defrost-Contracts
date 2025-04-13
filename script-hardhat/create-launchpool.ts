import { ethers } from "hardhat";

// Define the contract ABI
async function main(testParams: {
	proxyAddress: string;
	vAssetAddress: string;
	projectTokenAddress: string;
}) {
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

	// Approve project tokens for ProjectHub
	const projectTokenAmount = ethers.toBigInt("1000000000000000000000000");
	const projectToken = await ethers.getContractAt(
		"MockERC20",
		testParams.projectTokenAddress,
		signer,
	);
	await (await projectToken.freeMint(projectTokenAmount)).wait();
	await (
		await projectToken.approve(testParams.proxyAddress, projectTokenAmount)
	).wait();

	const params = {
		projectId: projectId,
		projectTokenAmount: projectTokenAmount,
		projectToken: testParams.projectTokenAddress, // Project Token
		vAsset: testParams.vAssetAddress, // Voucher Imagination
		startBlock: startBlock,
		endBlock: endBlock,
		maxVTokensPerStaker: ethers.toBigInt("1000000000000000000"),
		changeBlocks: [startBlock, startBlock + 100n],
		emissionRateChanges: [
			ethers.toBigInt("1000000000000000000"),
			ethers.toBigInt("500000000000000000"),
		],
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
	proxyAddress: "0x2CD45db1754b74dddbE42F742BB10B70D0AC7819",
	vAssetAddress: "0xD02D73E05b002Cb8EB7BEf9DF8Ed68ed39752465",
	projectTokenAddress: "0x96b6D28DF53641A47be72F44BE8C626bf07365A8",
}).catch(console.error);
