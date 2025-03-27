// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";

// import { MockLaunchpool }

contract SetupStakers is Test {
	function createAndApprove(
		uint256 stakerCount,
		address launchpoolAddr,
		address vAsset
	) public returns (address[] memory) {
		// Generate a random salt for the stakers
		uint256 salt = uint256(
			keccak256(
				abi.encodePacked(
					block.timestamp,
					block.prevrandao,
					stakerCount,
					msg.sender,
					tx.origin,
					block.coinbase
				)
			)
		);
		address[] memory stakers = new address[](stakerCount);
		for (uint i; i < stakerCount; i++) {
			address newStaker = makeAddr(
				string(abi.encodePacked("staker ", i, salt))
			);
			stakers[i] = newStaker;
			MockERC20(vAsset).freeMintTo(newStaker, 1e55);
			vm.prank(newStaker);
			MockERC20(vAsset).approve(launchpoolAddr, 1e55);
		}
		return stakers;
	}
}
