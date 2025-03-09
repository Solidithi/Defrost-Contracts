// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Upgrades } from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import { ProjectHubUpgradeable } from "@src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { Context } from "@openzeppelin/contracts/access/Ownable.sol";
import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

contract DeployProjectHub is Context, Script {
	address[] public vAssets;
	address[] public nativeAssets;

	function run(address[] calldata _vAssets) external {
		setVAssets(_vAssets);
		deployProjectHub();
	}

	function setVAssets(address[] memory _vAssets) public {
		vAssets = _vAssets;
	}

	function setNativeAsets(address[] memory _nativeAssets) public {
		nativeAssets = _nativeAssets;
	}

	/**
	 * @notice for testing purpose only
	 */
	function deployProjectHub() public returns (address projectHubAddress) {
		projectHubAddress = address(new ProjectHubUpgradeable());
		ProjectHubUpgradeable(projectHubAddress).initialize(
			_msgSender(),
			vAssets,
			nativeAssets
		);

		console.log(
			"Deployed ProjectHubUpgradable at address: %s",
			projectHubAddress
		);
		return projectHubAddress;
	}

	function run() public {
		deployProjectHub();
	}
}
