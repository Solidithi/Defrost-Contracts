// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	constructor(string memory name, string memory symbol) ERC20(name, symbol) {
		_mint(msg.sender, 1e20 * (10 ** decimals()));
	}

	function freeMint(uint256 amount) public {
		_mint(msg.sender, amount);
	}

	function freeMintTo(address to, uint256 amount) public {
		_mint(to, amount);
	}
}
