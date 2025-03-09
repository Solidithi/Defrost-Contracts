/**
 * Deployment info for a contract or library.
 * This is a structured deployment info that can be saved to a file.
 */
export interface DeploymentInfo {
	name: string; // Contract/Library name
	type: "contract" | "library";
	address: string; // Deployed address
	commitHash: string; // Git commit hash (for improved tracing of code changes)
	deploymentTime: string; // ISO timestamp (e.g. "2025-01-01T00:00:00Z")
	deployer: string; // Deployer address
	constructorArgs?: Record<string, any>; // Constructor arguments
	linkedLibraries?: {
		// Externally linked libraries (if any)
		[libraryName: string]: string; // Library name -> address, e.g. {"ProjectLibrary": "0x1234..."}
	};
	version: `v${number}` | "increment"; // Version tag (v1, v2, etc.) or "increment" for auto-increment

	// Upgradeable-specific info:
	isUpgradeSafe: boolean; // Is this contract/library upgrade-safe?
	upgradeability?: {
		pattern: "transparent" | "uups" | "diammond" | "beacon"; // Upgradeable pattern
		isProxy: boolean; // Is this a proxy contract?
		proxyAddress?: string; // Proxy address (if applicable)
		proxyAdminAddress?: string; // Proxy admin contract address (if applicable)
		adminAddress?: string; // Admin address (if applicable)
		implementationAddress?: string; // Implementation address (if applicable)
		initializerArgs?: Record<string, any>; // Initializer arguments (if applicable)
	};

	// Additional metadata
	verified?: boolean; // Whether verified on block explorer
	license?: string; // License type
	abi?: any[]; // Contract ABI
	bytecode?: string; // Contract bytecode
}
