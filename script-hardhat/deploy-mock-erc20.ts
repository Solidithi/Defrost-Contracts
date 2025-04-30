import { ethers } from "hardhat";
import { logDeployment, getLatestCommitHash } from "./utils";

async function main() {
	const chainId = await ethers.provider
		.getNetwork()
		.then((n) => Number(n.chainId));
	const [signer] = await ethers.getSigners();
	const deployerAddress = await signer.getAddress();
	const latestCommitHash = getLatestCommitHash();

	// Deploy mock Voucher Token
	const vFactory = await ethers.getContractFactory("MockERC20", signer);
	const vContract = await vFactory.deploy("Voucher Imagination", "VI");
	await vContract.waitForDeployment();
	const vAddress = await vContract.getAddress();
	console.log(`Voucher Imagination deployed at: ${vAddress}`);
	logDeployment(chainId, {
		name: "MockVToken",
		type: "contract",
		address: vAddress,
		deploymentTime: new Date().toISOString(),
		deployer: deployerAddress,
		commitHash: latestCommitHash,
		version: "increment",
		constructorArgs: {
			name: "Voucher Imagination",
			symbol: "VI",
		},
		isUpgradeSafe: false,
	});

	// Deploy mock Native Token
	const nFactory = await ethers.getContractFactory("MockERC20", signer);
	const nContract = await nFactory.deploy("Native Token", "NAT");
	await nContract.waitForDeployment();
	const nAddress = await nContract.getAddress();
	console.log(`Native token deployed at: ${nAddress}`);
	logDeployment(chainId, {
		name: "MockNativeToken",
		type: "contract",
		address: nAddress,
		deploymentTime: new Date().toISOString(),
		deployer: deployerAddress,
		commitHash: latestCommitHash,
		version: "increment",
		constructorArgs: {
			name: "Native Token",
			symbol: "NAT",
		},
		isUpgradeSafe: false,
	});

	// Deploy mock Project Token
	const pFactory = await ethers.getContractFactory("MockERC20", signer);
	const pContract = await pFactory.deploy("Project Token", "PRO");
	await pContract.waitForDeployment();
	const pAddress = await pContract.getAddress();
	console.log(`Project token deployed at: ${pAddress}`);
	logDeployment(chainId, {
		name: "MockProjectToken",
		type: "contract",
		address: pAddress,
		deploymentTime: new Date().toISOString(),
		deployer: deployerAddress,
		commitHash: latestCommitHash,
		version: "increment",
		constructorArgs: {
			name: "Project Token",
			symbol: "PRO",
		},
		isUpgradeSafe: false,
	});
}

main().catch((err) => console.error(err));
