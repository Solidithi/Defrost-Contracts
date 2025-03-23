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

contract CustomDeployAddress is Test {
	MockXCMOracle public mockXCMOracle;

	function setUp() public {
		// Put MockXCMOracle at the hard-coded address of real on-chain XCMOracle
		mockXCMOracle = new MockXCMOracle(12000, 10, 100);
		deployCodeTo("MockXCMOracle", mockXCMOracle.ORACLE_ONCHAIN_ADDRESS());
	}

	function test_mock_oracle_interactive() public view {
		uint256 nativeAmount = IXCMOracle(address(mockXCMOracle))
			.getTokenByVToken(address(this), 10 ether);
		assertTrue(
			nativeAmount > 0,
			"Native amount should be greater than 0 if mock oracle is working"
		);
	}
}
