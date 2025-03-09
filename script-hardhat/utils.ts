import fs from "fs";
import path from "path";
import { DeploymentInfo } from "./types";
import {
	ContractFactory,
	ParamType,
	Interface,
	FunctionFragment,
} from "ethers";
import { execSync } from "child_process";
import chainManifest from "../chain-manifest.json";

// Log deployment info to a JSON file
export function logDeployment(
	chainId: number,
	deploymentInfo: DeploymentInfo,
	logOptions?: {
		writeAbiToPath?: string; // e.g. write ABI to front-end's dir
		writeBytecodeToPath?: string;
	},
) {
	// Create directories if they don't exist
	const chain =
		chainManifest[chainId.toString() as keyof typeof chainManifest];
	const chainDir = path.join(
		"./deployments",
		chainId.toString() + "_" + chain.name,
	);
	if (!fs.existsSync(chainDir)) {
		fs.mkdirSync(chainDir, { recursive: true });
	}

	// Read existing JSON deployment info file
	const filePath = getDeploymentInfoPath(chainId, deploymentInfo.name);
	if (!fs.existsSync(filePath)) {
		fs.writeFileSync(filePath, "[]");
	}

	// Validate upgradeable contract version
	if (deploymentInfo.version) {
		const latestVersion = getLatestContractVersion(
			chainId,
			deploymentInfo.name,
		);
		if (deploymentInfo.version === "increment") {
			deploymentInfo.version = ("v" +
				String(latestVersion + 1)) as `v${number}`;
		}
		if (!deploymentInfo.version.startsWith("v"))
			throw new Error(`Invalid version tag: ${deploymentInfo.version}`);

		const version = parseInt(deploymentInfo.version.slice(1));
		if (version <= latestVersion)
			throw new Error(
				`Version ${version} is not greater than the latest version.`,
			);
	}

	const existingDeployments = <DeploymentInfo[]>(
		JSON.parse(fs.readFileSync(filePath, "utf8"))
	);

	// Append to JSON file
	existingDeployments.push(deploymentInfo);
	fs.writeFileSync(filePath, JSON.stringify(existingDeployments, null, 4));

	// TODO: implement log options

	console.log(
		`Deployment info of ${deploymentInfo.name} logged to file:`,
		filePath,
	);
}

export function preDeploymentCheck(chainId: number) {
	// Check if there are uncommitted changes to the .sol files
	// if deploying to a non-local chain
	const isLocalChain =
		chainManifest[chainId.toString() as keyof typeof chainManifest].type ===
		"local";
	if (isLocalChain) return;

	const output = execSync("git status -s src/").toString();

	if (output.trim()) {
		const uncommittedFiles = output
			.split("\n")
			.filter((line) => line.trim() && line.includes(".sol"))
			.map((line) => line.trim());

		if (uncommittedFiles.length > 0) {
			console.warn(
				"⚠️ DEADLY WARNING: You have uncommitted changes in Solidity files:",
			);
			uncommittedFiles.forEach((file) => console.warn(`  ${file}`));
			console.warn(
				"It's recommended to build, test, commit your changes before deployment.",
			);

			throw new Error("Cannot deploy with uncommitted Solidity files.");
		}
	} else {
		console.log("✓ All Solidity files are committed.");
	}
}

export function getLatestCommitHash(): string {
	const commitHash = require("child_process")
		.execSync("git rev-parse HEAD")
		.toString()
		.trim();
	return commitHash;
}

export function isChainSupported(chainId: number): boolean {
	return Object.keys(chainManifest).includes(chainId.toString());
}

export function isContractDeployedToChain(
	chainId: number,
	contractOrLibName: string,
): boolean {
	if (!isChainSupported(chainId)) {
		throw new Error(`Chain ID ${chainId} is not supported.`);
	}
	const deploymentInfoPath = getDeploymentInfoPath(
		chainId,
		contractOrLibName,
	);
	return fs.existsSync(deploymentInfoPath);
}

export function getDeploymentInfoPath(
	chainId: number,
	contractOrLibName: string,
): string {
	if (!isChainSupported(chainId)) {
		throw new Error(`Chain ID ${chainId} is not supported.`);
	}

	const chain =
		chainManifest[chainId.toString() as keyof typeof chainManifest];
	return path.join(
		"./deployments",
		chainId.toString() + "_" + chain.name,
		`${contractOrLibName}.json`,
	);
}

export function getLatestContractVersion(
	chainId: number,
	contractOrLibName: string,
): number {
	if (!isChainSupported(chainId)) {
		throw new Error(`Chain ID ${chainId} is not supported.`);
	}

	const chainIdStr = <keyof typeof chainManifest>chainId.toString();
	const chain = chainManifest[chainIdStr];

	// For first deployment, return 0 instead of throwing an error
	if (!isContractDeployedToChain(chainId, contractOrLibName)) {
		console.log(
			`First deployment of ${contractOrLibName} on chain ${chainId} (${chain.name})`,
		);
		return 0;
	}

	try {
		const deploymentInfoPath = getDeploymentInfoPath(
			chainId,
			contractOrLibName,
		);
		const fileContent = fs.readFileSync(deploymentInfoPath, "utf8");

		// Handle empty files
		if (!fileContent.trim()) {
			return 0;
		}

		const deployments = <DeploymentInfo[]>JSON.parse(fileContent);

		// Handle empty arrays
		if (!deployments || deployments.length === 0) {
			return 0;
		}

		// Find highest version
		// let highestVersion = 0;
		const newestDeployment = deployments.reduce(
			(newestDeployment, currDeployment) => {
				const newestVersion = parseInt(
					newestDeployment.version.slice(1),
				);
				const currVersion = parseInt(currDeployment.version.slice(1));
				return currVersion > newestVersion
					? currDeployment
					: newestDeployment;
			},
			deployments[0],
		);
		const newestVersion = parseInt(newestDeployment.version.slice(1));
		// for (const info of deployments) {
		// 	try {
		// 		const version = parseInt(info.version.slice(1));
		// 		if (!isNaN(version) && version > highestVersion) {
		// 			highestVersion = version;
		// 		}
		// 	} catch (e) {
		// 		console.error(`Error parsing version: ${info.version}`);
		// 	}
		// }

		console.log(
			`Found highest version ${newestVersion} for ${contractOrLibName}`,
		);
		return newestVersion;
	} catch (error) {
		console.error(`Error reading deployment info: ${error}`);
		return 0; // Default to 0 on error
	}
}

/**
 *
 * @param contractFactory
 * @param functionNameOrSig
 * @param args
 * @returns
 */
export async function getNamedFunctionArgs<
	TypechainContractFactory extends ContractFactory,
	FunctionNameOrSig extends string,
>(
	contractFactory: TypechainContractFactory,
	functionNameOrSig: FunctionNameOrSig,
	args: any[],
): Promise<Record<string, any> | undefined> {
	try {
		let fragment;

		// Special handling for constructor
		if (functionNameOrSig.toLowerCase() === "constructor") {
			// Access the ABI directly to find the constructor
			const contractName = (contractFactory as any).name.replace(
				"__factory",
				"",
			);
			const abi = require(
				path.join(
					"../out",
					`${contractName}.sol`,
					`${contractName}.json`,
				),
			).abi;

			// Find constructor in the ABI
			fragment = abi.find((item: any) => item.type === "constructor");
		} else {
			// Normal function - use interface
			const contractIface = (
				contractFactory as any
			).createInterface() as Interface;
			fragment = contractIface.getFunction(functionNameOrSig as string);
		}

		if (!fragment) {
			throw new Error(
				`Function ${functionNameOrSig} not found in interface.`,
			);
		}

		// Extract parameter names from function fragment
		const inputs = (fragment as FunctionFragment).inputs || [];
		if (inputs.length !== args.length) {
			throw new Error(
				`Incorrect number of arguments for function ${functionNameOrSig}: ${args.length} provided, ${inputs.length} expected.`,
			);
		}

		const paramNames = inputs.map(
			(input: ParamType) => input.name || "unnamed",
		);

		// Create structured arguments
		return Object.fromEntries(
			paramNames.map((name: string, i: number) => [name, args[i]]),
		);
	} catch (error) {
		console.error(`Error in getNamedFunctionArgs: ${error}`);
		// Fallback to simple numbered arguments if all else fails
		// return Object.fromEntries(args.map((arg, i) => [`arg${i + 1}`, arg]));
	}
}
