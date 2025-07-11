import { ethers } from "hardhat";
import { logDeployment, getLatestCommitHash } from "./utils";

interface deployLaunchpoolLibraryConfig {
	chainId: number;
}

export async function deployLaunchpoolLibrary({
	chainId,
}: deployLaunchpoolLibraryConfig) {
	let launchpoolLib;
	const launchpoolLibFactory =
		await ethers.getContractFactory("LaunchpoolLibrary");
	launchpoolLib = await launchpoolLibFactory.deploy();
	await launchpoolLib.waitForDeployment();
	const launchpoolLibAddress = await launchpoolLib.getAddress();
	console.log("Launchpool library deployed to:", launchpoolLibAddress);

	// Log deployment info for LaunchpoolLibrary
	const latestCommitHash = getLatestCommitHash();
	const [deployer] = await ethers.getSigners();
	logDeployment(chainId, {
		name: "LaunchpoolLibrary",
		type: "library",
		address: launchpoolLibAddress,
		commitHash: latestCommitHash,
		deploymentTime: new Date().toISOString(),
		deployer: deployer.address,
		version: "increment",
		isUpgradeSafe: true,
	});

	return launchpoolLib;
}

interface DeployProjectLibraryConfig {
	chainId: number;
}

export async function deployProjectLibrary({
	chainId,
}: DeployProjectLibraryConfig) {
	const projectLibFactory = await ethers.getContractFactory("ProjectLibrary");
	let projectLib;

	projectLib = await projectLibFactory.deploy();
	projectLib.waitForDeployment();
	const projectLibAddress = await projectLib.getAddress();
	console.log("ProjectLib deployed to: ", projectLibAddress);

	// Log deployment info for ProjectLib
	const latestCommitHash = getLatestCommitHash();
	const [deployer] = await ethers.getSigners();
	logDeployment(chainId, {
		name: "ProjectLibrary",
		type: "library",
		address: projectLibAddress,
		commitHash: latestCommitHash,
		deploymentTime: new Date().toISOString(),
		deployer: deployer.address,
		version: "increment",
		isUpgradeSafe: true,
	});

	return projectLib;
}
