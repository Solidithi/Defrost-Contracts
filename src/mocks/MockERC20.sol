// SPDX-License-Identifier: MIT
/* solhint-disable */
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	uint8 internal customDecimals;

	constructor(string memory name, string memory symbol) ERC20(name, symbol) {
		_mint(msg.sender, 1e20 * (10 ** decimals()));
	}

	function freeMint(uint256 amount) public {
		_mint(msg.sender, amount);
	}

	function freeMintTo(address to, uint256 amount) public {
		_mint(to, amount);
	}

	function setDecimals(uint8 _decimals) public {
		customDecimals = _decimals;
	}

	function decimals() public view override returns (uint8) {
		return (customDecimals == 0) ? super.decimals() : customDecimals;
	}
}
/* solhint-enable */
