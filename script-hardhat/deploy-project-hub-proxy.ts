import { ethers, upgrades } from "hardhat";
import { logDeployment } from "./utils";
import { preDeploymentCheck, getLatestCommitHash } from "./utils";
import { getNamedFunctionArgs } from "./utils";
import { ProjectHubUpgradeable__factory } from "../typechain-types";

async function deployProjectHubProxy() {
	const chainId = await ethers.provider
		.getNetwork()
		.then((n) => Number(n.chainId));
	preDeploymentCheck(chainId);

	const [deployer] = await ethers.getSigners();

	// Deploy libraries
	console.log("Deploying libraries...");

	const projectLibFactory = await ethers.getContractFactory("ProjectLibrary");
	const projectLib = await projectLibFactory.deploy();
	await projectLib.waitForDeployment();
	const projectLibAddress = await projectLib.getAddress();
	console.log("ProjectLib library deployed to:", projectLibAddress);

	const launchpoolLibFactory =
		await ethers.getContractFactory("LaunchpoolLibrary");
	const launchpoolLib = await launchpoolLibFactory.deploy();
	await launchpoolLib.waitForDeployment();
	const launchpoolLibAddress = await launchpoolLib.getAddress();
	console.log("Launchpool library deployed to:", launchpoolLibAddress);

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
	const vAssets = ["0x0000000000000000000000000000000000000001"];

	const projectHubProxy = await upgrades.deployProxy(
		ProjectHubFactory,
		[await deployer.getAddress(), vAssets],
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
	const deployerAddress = await deployer.getAddress();
	const latestCommitHash = getLatestCommitHash();

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

	// Log deployment info for ProjectHub
	logDeployment(chainId, {
		name: "ProjectHubUpgradable",
		type: "contract",
		address: projectHubProxyAddress,
		commitHash: latestCommitHash,
		deploymentTime: new Date().toISOString(),
		deployer: deployerAddress,
		version: "increment",
		constructorArgs: await getNamedFunctionArgs(
			ProjectHubUpgradeable__factory as any,
			"constructor",
			[await deployer.getAddress(), vAssets],
		),
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
				[await deployer.getAddress(), vAssets],
			),
		},
	});

	return projectHubProxy;
}

async function main() {
	try {
		await deployProjectHubProxy();
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
