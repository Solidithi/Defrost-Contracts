import { ethers, upgrades } from "hardhat";
import { logDeployment } from "./utils";
import { preDeploymentCheck, getLatestCommitHash } from "./utils";
import { getNamedFunctionArgs } from "./utils";
import { ProjectHubUpgradeable__factory } from "../typechain-types";

async function deployProjectHubProxy(
	vAssets: string[],
	nativeAssets: string[],
	projectLibAddress?: string,
	launchpoolLibAddress?: string,
) {
	const chainId = await ethers.provider
		.getNetwork()
		.then((n) => Number(n.chainId));
	// preDeploymentCheck(chainId); TODO: Turn this on later

	const [deployer] = await ethers.getSigners();
	const deployerAddress = await deployer.getAddress();
	const latestCommitHash = getLatestCommitHash();

	// Deploy libraries
	console.log("Deploying libraries...");

	let projectLib;
	if (!!projectLibAddress) {
		projectLib = await ethers.getContractAt(
			"ProjectLibrary",
			projectLibAddress,
		);
		console.log("ProjectLib retrieved from address: ", projectLibAddress);
	} else {
		const projectLibFactory =
			await ethers.getContractFactory("ProjectLibrary");
		projectLib = await projectLibFactory.deploy();
		projectLib.waitForDeployment();
		projectLibAddress = await projectLib.getAddress();
		console.log("ProjectLib deployed to: ", projectLibAddress);
		// Log deployment info for ProjectLib
		logDeployment(chainId, {
			name: "ProjectLibrary",
			type: "library",
			address: projectLibAddress,
			commitHash: latestCommitHash,
			deploymentTime: new Date().toISOString(),
			deployer: deployerAddress,
			version: "increment",
			isUpgradeSafe: true,
		});
	}

	let launchpoolLib;
	if (!!launchpoolLibAddress) {
		launchpoolLib = await ethers.getContractAt(
			"LaunchpoolLibrary",
			launchpoolLibAddress,
		);
		console.log(
			"LaunchpoolLib retrieved from address: ",
			launchpoolLibAddress,
		);
	} else {
		const launchpoolLibFactory =
			await ethers.getContractFactory("LaunchpoolLibrary");
		launchpoolLib = await launchpoolLibFactory.deploy();
		await launchpoolLib.waitForDeployment();
		launchpoolLibAddress = await launchpoolLib.getAddress();
		console.log("Launchpool library deployed to:", launchpoolLibAddress);
		// Log deployment info for LaunchpoolLibrary
		logDeployment(chainId, {
			name: "LaunchpoolLibrary",
			type: "library",
			address: launchpoolLibAddress,
			commitHash: latestCommitHash,
			deploymentTime: new Date().toISOString(),
			deployer: deployerAddress,
			version: "increment",
			isUpgradeSafe: true,
		});
	}

	// Create ProjectHubFactory and link libraries
	const ProjectHubFactory = await ethers.getContractFactory(
		"ProjectHubUpgradeable",
		{
			libraries: {
				ProjectLibrary: await projectLib.getAddress(),
				LaunchpoolLibrary: await launchpoolLib.getAddress(),
			},
		},
	);

	// Deploy ProjectHubUpgradeable proxy
	console.log("Deploying ProjectHub proxy...");
	// TODO: Update vAssets and nativeAssets to pass in real data
	const projectHubInitArgs = [deployerAddress, vAssets, nativeAssets];
	const projectHubProxy = await upgrades.deployProxy(
		ProjectHubFactory,
		projectHubInitArgs,
		{
			initializer: "initialize",
			kind: "transparent",
			unsafeAllow: ["external-library-linking"],
		},
	);
	await projectHubProxy.waitForDeployment();
	const projectHubProxyAddress = await projectHubProxy.getAddress();
	console.log(
		"ProjectHubUpgradeable proxy deployed to:",
		projectHubProxyAddress,
	);

	// After deployment
	const adminAddress = await upgrades.erc1967.getAdminAddress(
		await projectHubProxy.getAddress(),
	);
	const implAddress = await upgrades.erc1967.getImplementationAddress(
		await projectHubProxy.getAddress(),
	);

	// Log deployment info for ProjectHub
	logDeployment(chainId, {
		name: "ProjectHubUpgradable",
		type: "contract",
		address: implAddress,
		commitHash: latestCommitHash,
		deploymentTime: new Date().toISOString(),
		deployer: deployerAddress,
		version: "increment",
		linkedLibraries: {
			ProjectLibrary: projectLibAddress,
			LaunchpoolLibrary: launchpoolLibAddress,
		},
		isUpgradeSafe: true,
		upgradeability: {
			pattern: "transparent",
			isProxy: true,
			proxyAddress: projectHubProxyAddress,
			proxyAdminAddress: adminAddress,
			implementationAddress: implAddress,
			initializerArgs: await getNamedFunctionArgs(
				ProjectHubUpgradeable__factory as any,
				"initialize",
				projectHubInitArgs,
			),
		},
	});

	return projectHubProxy;
}

async function main() {
	try {
		await deployProjectHubProxy(
			["0xBc6137154f4EBf64Ee355e8774A7467B1d0CfF29"], // Voucher Imagination
			["0x198F2832AFe856CD5CdABAbA9EEAecAb6be95652"], // Native Token
		);
	} catch (error) {
		console.error("Deployment failed:", error);
		process.exit(1);
	}
}

main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
