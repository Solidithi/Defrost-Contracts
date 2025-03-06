// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Upgrades } from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import { ProjectHubUpgradeable } from "@src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { Context } from "@openzeppelin/contracts/access/Ownable.sol";
import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

contract DeployProjectHubProxy is Context, Script {
	address[] public vAssets;

	function run(address[] calldata _vAssets) external {
		setVAssets(_vAssets);
		deployProjectHubProxy();
	}

	function setVAssets(address[] memory _vAssets) public {
		vAssets = _vAssets;
	}

	function deployProjectHubProxy() public returns (address proxyAddress) {
		proxyAddress = Upgrades.deployUUPSProxy(
			"ProjectHubUpgradeable.sol:ProjectHubUpgradeable",
			abi.encodeCall(
				ProjectHubUpgradeable.initialize,
				(_msgSender(), vAssets)
			)
		);

		console.log(
			"Deployed UUPS ProjectHubUpgradable at address: %s",
			proxyAddress
		);
		return proxyAddress;
	}

	function run() public {
		deployProjectHubProxy();
	}
}
