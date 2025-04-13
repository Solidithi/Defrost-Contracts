import { ethers } from "hardhat";
import { logDeployment, getLatestCommitHash } from "./utils";

async function main() {
	console.log("Deploying MockXCMOracle to Moonbase Alpha...");

	// Check if we're on the correct network
	const network = await ethers.provider.getNetwork();
	const chainId = Number(network.chainId);

	if (chainId !== 1287) {
		console.warn(
			`Warning: Expected Moonbase Alpha (1287), but connected to chain ID ${chainId}`,
		);
		// throw new Error(`Expected Moonbase Alpha (1287), but connected to chain ID ${chainId}`);
	}

	const [deployer] = await ethers.getSigners();
	console.log(`Deploying contracts with the account: ${deployer.address}`);

	// Moonbase Alpha block time is ~6seconds
	const MOONBEAM_BLOCK_TIME = 6;

	// Constructor parameters
	const initialRate = ethers.parseEther("1.0"); // Initial exchange rate 1.0
	const blockInterval = 10n; // Update exchange rate every 10 blocks
	const apy = 100_000n; // 10% APY (10.0000%)

	// Deploy the contract
	const MockXCMOracle = await ethers.getContractFactory("MockXCMOracle");
	const mockXCMOracle = await MockXCMOracle.deploy(
		initialRate,
		blockInterval,
		apy,
		MOONBEAM_BLOCK_TIME,
	);

	await mockXCMOracle.waitForDeployment();
	const address = await mockXCMOracle.getAddress();

	console.log(`MockXCMOracle deployed to: ${address}`);
	console.log("Deployment parameters:");
	console.log(
		`- Initial rate: ${ethers.formatEther(initialRate)} (${initialRate})`,
	);
	console.log(`- Block interval: ${blockInterval}`);
	console.log(`- APY: ${Number(apy) / 10_000}%`);
	console.log(`- Network block time: ${MOONBEAM_BLOCK_TIME} seconds`);

	// Log deployment information
	const deployerAddress = await deployer.getAddress();
	const latestCommitHash = getLatestCommitHash();

	logDeployment(chainId, {
		name: "MockXCMOracle",
		type: "contract",
		address: address,
		commitHash: latestCommitHash,
		deploymentTime: new Date().toISOString(),
		deployer: deployerAddress,
		version: "v1",
		isUpgradeSafe: false,
		constructorArgs: {
			_initialRate: initialRate.toString(),
			_blockInterval: blockInterval.toString(),
			_apy: apy.toString(),
			_networkBlockTime: MOONBEAM_BLOCK_TIME,
		},
	});

	// Return the address for testing purposes
	return address;
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
