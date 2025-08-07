import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-preprocessor";
import "@typechain/hardhat";
import { HardhatUserConfig } from "hardhat/types";
import * as fs from "node:fs";
import "dotenv/config";

// Parse env variables
const privateKeys = (process.env.PRIVATE_KEYS || "").split(",");
const devPrivateKeys = [
	// "3f5c38d6e87a9a91f4ddc80f6f57bc8bbbe59619911c01d5a47003a1a79117bd", // Inject Minh EVM for testing
	"0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
	"0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
	"0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
	"0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
	"0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
	"0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",
	"0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e",
	"0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356",
	"0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97",
	"0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6",
];

function getRemappings() {
	return fs
		.readFileSync("remappings.txt", "utf8")
		.split("\n")
		.filter(Boolean) // remove empty lines
		.map((line: string) => line.trim().split("="));
}

// Export config
const config: HardhatUserConfig = {
	defaultNetwork: "localhost",
	networks: {
		localhost: {
			url: "http://localhost:8545",
			accounts: devPrivateKeys,
			loggingEnabled: true,
			chainId: 31337,
		},
		sepolia: {
			url: "https://eth-sepolia.g.alchemy.com/v2/vmbHGNAV4NKw9V2tleUXODo4NDDUQpiy",
			accounts: privateKeys,
			loggingEnabled: true,
			chainId: 11155111,
		},
		moonbase_alpha: {
			url: "https://rpc.api.moonbase.moonbeam.network",
			accounts: privateKeys,
			loggingEnabled: true,
			chainId: 1287,
		},
		westend: {
			url: "https://westend-asset-hub-eth-rpc.polkadot.io",
			accounts: privateKeys,
			loggingEnabled: true,
			chainId: 1000,
		},
	},
	solidity: {
		version: "0.8.26",
		settings: {
			viaIR: true,
			optimizer: {
				enabled: true,
				runs: 200,
			},
		},
	},
	paths: {
		sources: "./src",
		tests: "./test-hardhat",
		cache: "./cache-hardhat",
		artifacts: "./out-hardhat",
	},

	mocha: {
		timeout: 40000,
	},

	// Advanced configs
	typechain: {
		outDir: "typechain-types",
		target: "ethers-v6",
		alwaysGenerateOverloads: true,
		externalArtifacts: ["./artifacts/*.json"],
	},

	// Adapt to foundry's remappings in remappings.txt
	preprocess: {
		eachLine: (hre) => ({
			transform: (line: string) => {
				if (line.match(/".*.sol";$/)) {
					// match all lines with `"<any-import-path>.sol";`
					for (const [from, to] of getRemappings()) {
						if (line.includes(from)) {
							line = line.replace(from, to);
							break;
						}
					}
				}
				return line;
			},
		}),
	},
};

export default config;
