// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { ProjectHubUpgradeable } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { DeployProjectHubProxyCustomSender } from "../testutils/DeployProjectHubProxyCustomSender.sol";
import { ProjectHubUpgradeable } from "../../src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";
import { DeployMockXCMOracle } from "../testutils/DeployMockXCMOracle.sol";

contract CustomDeployAddress is Test {
	DeployMockXCMOracle mockXCMOracleDeployer = new DeployMockXCMOracle();
	address mockXCMOracleAddr;

	function setUp() public {
		// Put MockXCMOracle at the hard-coded address of real on-chain XCMOracle
		mockXCMOracleDeployer.deploy(12000, 10, 80000, 6);
		mockXCMOracleAddr = mockXCMOracleDeployer.ORACLE_ONCHAIN_ADDRESS();
	}

	function test_mock_oracle_interactive() public view {
		IXCMOracle.PoolInfo memory pool = IXCMOracle(mockXCMOracleAddr)
			.tokenPool(0x0806);
		assertTrue(
			pool.assetAmount > 0 && pool.vAssetAmount > 0,
			"Pool info should be set"
		);
	}
}
