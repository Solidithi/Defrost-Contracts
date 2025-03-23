// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { Upgrades } from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import { ProjectHubUpgradeable } from "@src/upgradeable/v1/ProjectHubUpgradeable.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { Context } from "@openzeppelin/contracts/access/Ownable.sol";
import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";

contract DeployMockXCMOracle is Script, Test {
	address public constant ORACLE_ONCHAIN_ADDRESS =
		0xEF81930Aa8ed07C17948B2E26b7bfAF20144eF2a;

	function deploy(
		uint256 _baseExchangeRate,
		uint256 _blockInterval,
		uint256 _incrementAmount
	) public returns (address) {
		deployCodeTo(
			"MockXCMOracle",
			abi.encode(_baseExchangeRate, _blockInterval, _incrementAmount),
			ORACLE_ONCHAIN_ADDRESS
		);

		return ORACLE_ONCHAIN_ADDRESS;
	}
}
