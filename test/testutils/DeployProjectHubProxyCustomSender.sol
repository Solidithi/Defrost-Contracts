// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { DeployProjectHubProxy } from "./DeployProjectHubProxy.sol";

contract DeployProjectHubProxyCustomSender is DeployProjectHubProxy {
	address sender;

	constructor(
		address[] memory _vAssets,
		address[] memory _nativeAssets,
		address _sender
	) DeployProjectHubProxy() {
		setSender(_sender);
		setVAssets(_vAssets);
		setNativeAssets(_nativeAssets);
	}

	function setSender(address _sender) public {
		sender = _sender;
	}

	function _msgSender() internal view override returns (address) {
		return sender;
	}
}
