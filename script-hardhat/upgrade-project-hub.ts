import { ethers, upgrades, network } from "hardhat";
import { logDeployment, getLatestCommitHash } from "./utils";

/**
 * Simple script to upgrade a ProjectHub proxy to a new implementation
 * Usage examples:
 *
 * 1. Upgrade to existing implementation:
 *    upgradeToImplementation("0xProxyAddress", "0xNewImplementationAddress")
 *
 * 2. Deploy new implementation and upgrade:
 *    deployAndUpgrade("0xProxyAddress", "0xProjectLibAddress", "0xLaunchpoolLibAddress")
 */

/**
 * Upgrade proxy to an existing implementation address
 */
interface UpgradeToImplementationConfig {
	proxyAddress: string;
	newImplementationAddress: string;
}

interface DeployAndUpgradeConfig {
	proxyAddress: string;
	projectLibAddress: string;
	launchpoolLibAddress: string;
}

async function upgradeToImplementation({
	proxyAddress,
	newImplementationAddress,
}: UpgradeToImplementationConfig) {
	console.log("=== Upgrading to new project hub implementation ===");
	console.log("Proxy address:", proxyAddress);
	console.log("New implementation address:", newImplementationAddress);

	// Get current implementation for comparison
	const currentImplAddress =
		await upgrades.erc1967.getImplementationAddress(proxyAddress);
	console.log("Current implementation:", currentImplAddress);

	// Validate new implementation exists
	const code = await ethers.provider.getCode(newImplementationAddress);
	if (code === "0x") {
		throw new Error(`No contract found at: ${newImplementationAddress}`);
	}

	// Get the proxy admin contract
	const adminAddress = await upgrades.erc1967.getAdminAddress(proxyAddress);
	const proxyAdmin = await ethers.getContractAt(
		"ITransparentUpgradeableProxy",
		adminAddress,
	);

	// Directly upgrade to the specific implementation address using upgradeAndCall
	console.log("Upgrading proxy to specific implementation...");
	const tx = await proxyAdmin.upgradeToAndCall(
		newImplementationAddress,
		"0x",
	);
	await tx.wait();

	// Verify upgrade
	const finalImplAddress =
		await upgrades.erc1967.getImplementationAddress(proxyAddress);
	if (
		finalImplAddress.toLowerCase() !==
		newImplementationAddress.toLowerCase()
	) {
		throw new Error(
			`Upgrade failed: expected ${newImplementationAddress}, got ${finalImplAddress}`,
		);
	}
	console.log("Upgrade completed!");
	console.log("Previous implementation:", currentImplAddress);
	console.log("New implementation:", finalImplAddress);

	return {
		proxyAddress,
		previousImplementation: currentImplAddress,
		newImplementation: finalImplAddress,
	};
}

/**
 * Deploy new implementation and upgrade proxy
 */
async function deployAndUpgrade({
	proxyAddress,
	projectLibAddress,
	launchpoolLibAddress,
}: DeployAndUpgradeConfig) {
	console.log("=== Deploying new implementation and upgrading ===");
	console.log("Proxy address:", proxyAddress);
	console.log("ProjectLibrary address:", projectLibAddress);
	console.log("LaunchpoolLibrary address:", launchpoolLibAddress);

	const chainId = network.config.chainId;
	if (!chainId) {
		throw new Error("Chain ID is not defined!");
	}

	const [deployer] = await ethers.getSigners();
	const deployerAddress = await deployer.getAddress();
	const latestCommitHash = getLatestCommitHash();

	// Get current implementation for comparison
	const oldImplAddress =
		await upgrades.erc1967.getImplementationAddress(proxyAddress);
	console.log("Current implementation:", oldImplAddress);

	// Create factory with library linking
	const ProjectHubFactory = await ethers.getContractFactory(
		"ProjectHubUpgradeable",
		{
			libraries: {
				ProjectLibrary: projectLibAddress,
				LaunchpoolLibrary: launchpoolLibAddress,
			},
		},
	);

	// Manually deploy new implementation to bypass OpenZeppelin's duplicate detection
	console.log("Manually deploying new implementation contract...");
	const newImplementation = await ProjectHubFactory.deploy();
	await newImplementation.waitForDeployment();
	const newImplAddress = await newImplementation.getAddress();
	console.log("New implementation deployed to:", newImplAddress);

	// Get the proxy admin contract to perform manual upgrade
	const adminAddress = await upgrades.erc1967.getAdminAddress(proxyAddress);
	const proxyAdmin = await ethers.getContractAt("ProxyAdmin", adminAddress);

	// Upgrade to the new implementation
	console.log("Upgrading proxy to new implementation...");
	const upgradeTx = await proxyAdmin.upgradeAndCall(
		proxyAddress,
		newImplAddress,
		"0x", // No initialization call needed
	);
	await upgradeTx.wait();
	console.log("Upgrade transaction completed!");

	// Verify upgrade
	const finalImplAddress =
		await upgrades.erc1967.getImplementationAddress(proxyAddress);
	if (finalImplAddress.toLowerCase() !== newImplAddress.toLowerCase()) {
		throw new Error(
			`Upgrade verification failed: expected ${newImplAddress}, got ${finalImplAddress}`,
		);
	}
	console.log("Upgrade completed!");
	console.log("Previous implementation:", oldImplAddress);
	console.log("New implementation:", finalImplAddress);

	// Get admin address for comprehensive logging
	const proxyAdminAddress =
		await upgrades.erc1967.getAdminAddress(proxyAddress);

	// Log upgrade info
	logDeployment(chainId, {
		name: "ProjectHubUpgradable",
		type: "contract",
		address: newImplAddress,
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
			proxyAddress: proxyAddress,
			proxyAdminAddress: proxyAdminAddress,
			implementationAddress: newImplAddress,
		},
	});

	return {
		proxyAddress,
		previousImplementation: oldImplAddress,
		newImplementation: newImplAddress,
		newImplementationContract: newImplementation,
	};
}

async function main() {
	try {
		// ============================================
		// CONFIGURATION - Update these values
		// ============================================
		const PROXY_ADDRESS = "0xB8618EaEEbFf1c817e3DD32A2e27Ece62C9d2317"; // Replace with actual proxy address

		// Option 1: Upgrade to an existing implementation contract
		// const NEW_IMPLEMENTATION_ADDRESS = "0x0987654321098765432109876543210987654321"; // Replace with existing implementation
		// await upgradeToImplementation(PROXY_ADDRESS, NEW_IMPLEMENTATION_ADDRESS);

		// Option 2: Deploy new implementation and upgrade (comment out Option 1)
		const PROJECT_LIB_ADDRESS =
			"0x97C6A41de7b975eE772779bA8bEE60D7A71cb53F";
		const LAUNCHPOOL_LIB_ADDRESS =
			"0x1ABAeeB0bED9f38C03195dcCB18B4EE13F4ED556";
		await deployAndUpgrade({
			proxyAddress: PROXY_ADDRESS,
			projectLibAddress: PROJECT_LIB_ADDRESS,
			launchpoolLibAddress: LAUNCHPOOL_LIB_ADDRESS,
		});

		console.log("Upgrade completed successfully!");
	} catch (error) {
		console.error("Upgrade failed with error:", error);
		process.exit(1);
	}
}

// Only run if executed directly
if (require.main === module) {
	main()
		.then(() => process.exit(0))
		.catch((error) => {
			console.error(error);
			process.exit(1);
		});
}
