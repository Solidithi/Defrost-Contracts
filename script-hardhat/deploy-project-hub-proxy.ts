import { ethers, upgrades } from "hardhat";
import { logDeployment } from "./utils";
import { preDeploymentCheck, getLatestCommitHash } from "./utils";
import { getNamedFunctionArgs } from "./utils";
import { ProjectHubUpgradeable__factory } from "../typechain-types";
import { ContractTransactionReceipt } from "ethers";

// Define the configuration object type for deployProjectHubProxy
interface DeployProjectHubProxyConfig {
	vAssets: string[];
	nativeAssets: string[];
	xcmOracleAddress: string;
	projectLibAddress?: string;
	launchpoolLibAddress?: string;
}

async function deployProjectHubProxy(config: DeployProjectHubProxyConfig) {
	let {
		vAssets,
		nativeAssets,
		xcmOracleAddress,
		projectLibAddress,
		launchpoolLibAddress,
	} = config;

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
	// Include XCMOracle address in initialization arguments
	const projectHubInitArgs = [
		xcmOracleAddress,
		deployerAddress,
		vAssets,
		nativeAssets,
	];
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

	// Set mapping from vAssets to native assets
	const setMappingTxs: Promise<ContractTransactionReceipt | null>[] = [];
	for (let i = 0; i < vAssets.length; i++) {
		const vAsset = vAssets[i];
		const nativeAsset = nativeAssets[i];

		console.log(
			`Setting mapping from vToken ${vAsset} to native token ${nativeAsset}...`,
		);
		try {
			setMappingTxs.push(
				(
					await projectHubProxy.setNativeAssetForVAsset(
						vAsset,
						nativeAsset,
					)
				).wait(),
			);
		} catch (err) {
			console.error(
				`Failed to set mapping for vToken ${vAsset} to native token ${nativeAsset}:`,
				err,
			);
			console.log("You may need to set this mapping manually.");
		}
	}
	console.log("Waiting for all vAsset mapping txs to be mined...");
	await Promise.all(setMappingTxs);
	console.log("All vAssets mapping txs finished!");

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
		// Now deploy the ProjectHub with the MockXCMOracle address using the new config object
		await deployProjectHubProxy({
			vAssets: ["0xD02D73E05b002Cb8EB7BEf9DF8Ed68ed39752465"], // Voucher Imagination
			nativeAssets: ["0x7a4ebae8cA815b9F52F23a8AC9A2f707D4d4ff81"], // Native Token
			xcmOracleAddress: "0x288154C87Db809bc0d702CB46De40E5041b22071", // XCM Oracle
			// Comment these 2 lines below out for fresh deployment of libraries
			// projectLibAddress: "0xB6e25e0d45D2D7B5A337C09a73AC8c4739bB6Cce", // Project library
			// launchpoolLibAddress: "0xA33FCAf92DD13247291d5e6f9867064899753E17", // Launchpool library
		});
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
