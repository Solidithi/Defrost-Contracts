// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

contract SelfMultiCall {
	bytes32 public constant MULTICALL_SENDER_SLOT =
		keccak256("SelfMultiCall.ORIGINAL_SENDER_SLOT");

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

		_setMultiCallSender(msg.sender);

		for (uint256 i; i < len; ) {
			(bool success, bytes memory returnData) = address(this).call(
				callPayloadBatch[i]
			);
			if (!success) {
				_setMultiCallSender(address(0));
				revert MultiCallFailed(i, callPayloadBatch[i], returnData);
			}
			allReturnData[i] = returnData;

			unchecked {
				++i;
			}
		}

		_setMultiCallSender(address(0));
		return allReturnData;
	}

	function _setMultiCallSender(address sender) internal {
		bytes32 position = MULTICALL_SENDER_SLOT;
		assembly {
			sstore(position, sender)
		}
	}

	/**
	 * @notice Context-preserving version of msg.sender
	 * for use in selfMultiCall
	 */
	function _getMultiCallSender() internal view returns (address sender) {
		bytes32 position = MULTICALL_SENDER_SLOT;
		assembly {
			sender := sload(position)
		}
		return sender;
	}
}
