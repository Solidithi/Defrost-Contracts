// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { ProjectLibrary, LaunchpoolLibrary } from "@src/upgradeable/v1/ProjectHubUpgradeable.sol";

interface IProjectHub {
	// Functions
	function initialize(
		address _initialOwner,
		address[] calldata _initialVAssets
	) external;

	function createProject() external;

	function listPool(uint64 _poolId) external;

	function unlistProject(uint64 _poolId) external;

	function createLaunchpool(
		LaunchpoolLibrary.LaunchpoolCreationParams memory params
	) external returns (uint64);

	function setAcceptedVAsset(address _vAsset, bool _isAccepted) external;

	// Self Multi Call functions
	function multiCall(
		bytes[] calldata data
	) external returns (bytes[] memory results);

	// View Functions
	function projects(
		uint64 projectId
	) external view returns (ProjectLibrary.Project memory);

	function pools(
		uint64 poolId
	) external view returns (LaunchpoolLibrary.Pool memory);

	function acceptedVAssets(address _vAsset) external view returns (bool);

	function nextProjectId() external view returns (uint64);

	function nextPoolId() external view returns (uint64);

	function owner() external view returns (address);
}
