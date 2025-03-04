// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { DeployProjectHub } from "../../script/DeployProjectHub.sol";

contract DeployProjectHubModifiedSender is DeployProjectHub {
	address sender;

	constructor(address[] memory _vAssets, address _sender) DeployProjectHub() {
		setSender(_sender);
		setVAssets(_vAssets);
	}

	function setSender(address _sender) public {
		sender = _sender;
	}

	function _msgSender() internal view override returns (address) {
		return sender;
	}
}
