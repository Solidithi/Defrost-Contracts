// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract SelfMultiCall {
	error MultiCallFailed(
		uint256 callIndex,
		bytes callPayload,
		bytes errorPayload
	);

	/**
	 * @notice Executes multiple calls in a single transaction
	 * @param callPayloadBatch Array of encoded function calls
	 * @return allReturnData Array of return values
	 */
	function selfMultiCall(
		bytes[] calldata callPayloadBatch
	) external returns (bytes[] memory allReturnData) {
		uint256 len = callPayloadBatch.length;
		if (len == 0) {
			return new bytes[](0);
		}

		allReturnData = new bytes[](len);

		for (uint256 i; i < len; ) {
			(bool success, bytes memory returnData) = address(this).call(
				callPayloadBatch[i]
			);
			if (!success) {
				revert MultiCallFailed(i, callPayloadBatch[i], returnData);
			}
			allReturnData[i] = returnData;

			unchecked {
				++i;
			}
		}

		return allReturnData;
	}

	/**
	 * @notice Executes multiple view functions in a single call
	 * @param callPayloadBatch Array of encoded function calls
	 * @return Array of return values
	 */
	function selfMultiCallStatic(
		bytes[] calldata callPayloadBatch
	) external view returns (bytes[] memory) {
		uint256 len = callPayloadBatch.length;
		if (len == 0) return new bytes[](0);

		bytes[] memory allReturnData = new bytes[](len);

		for (uint256 i; i < len; ) {
			(bool success, bytes memory returnData) = address(this).staticcall(
				callPayloadBatch[i]
			);
			if (!success) {
				revert MultiCallFailed(i, callPayloadBatch[i], returnData);
			}
			allReturnData[i] = returnData;

			unchecked {
				++i;
			}
		}

		return allReturnData;
	}
}
