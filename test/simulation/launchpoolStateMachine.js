/**
 * @fileoverview State machine simulation for launchpool contract debugging
 *
 * @description
 * This module implements a prototype state machine that simulates the state transitions
 * of a launchpool contract. It is used for debugging purposes in a controlled environment.
 * The simulation handles staking mechanics, emission rate changes, and reward calculations.
 *
 * Core Components:
 * - Exchange rate tracking
 * - Block-based timing system
 * - Staker management
 * - Emission rate scheduling
 *
 */

// State variables
let cumulativeExchangeRate = 0n;
let startBlock = BigInt(100n);
const BLOCK_TIME_SECONDS = 6;
let poolDurationBlocks = BigInt((14 * 86400) / BLOCK_TIME_SECONDS);
let endBlock = startBlock + poolDurationBlocks;
let tickBlock = BigInt(startBlock);
let ownerShareOfInterest = 70n; // 70% default
let maxVAssetPerStaker = BigInt(1000 * 1e18);
let maxStakers = 0n;
let currentBlock = 0n;

let totalStaked = 0n;

// Block processing state
let lastProcessedChangeBlockIndex = 0;

// Addresses
let platformAdminAddress = "defrost";
// let projectToken = projectToken;
// let acceptedVAsset = acceptedVAsset;

// Rate changes
let changeBlocks = [
	startBlock,
	startBlock + poolDurationBlocks / 3n,
	startBlock + (poolDurationBlocks * 3n) / 4n,
];

// Initialize emission rate changes
let emissionRateChanges = new Map();
emissionRateChanges.set(changeBlocks[0], BigInt(10000 * 1e18));
emissionRateChanges.set(changeBlocks[1], BigInt(1000 * 1e18));
emissionRateChanges.set(changeBlocks[2], BigInt(900 * 1e18));

// Stakers mapping
let stakers = new Map();

function setCurrentBlock(_currentBlock) {
	currentBlock = _currentBlock;
}

function createStaker() {
	return {
		vAssetAmount: 0n,
		nativeTokenAmount: 0n,
		claimOffset: 0n,
	};
}

// Helper method to get staker info
function getStaker(address) {
	if (!stakers.has(address)) {
		stakers.set(address, createStaker());
	}
	return stakers.get(address);
}

function _getPendingExchangeRate() {
	// Early return if no stakes
	if (totalStaked === 0n) {
		return 0n;
	}

	let periodStartBlock = tickBlock;
	let periodEndBlock;
	let accumulatedIncrease = 0n;

	// Process all change blocks
	let i = lastProcessedChangeBlockIndex;
	for (; i < changeBlocks.length; i++) {
		periodEndBlock = changeBlocks[i];

		// Break if we've reached a future change block
		if (periodEndBlock >= currentBlock) {
			break;
		}

		if (periodEndBlock <= periodStartBlock) {
			continue;
		}

		// Calculate blocks elapsed in this period
		const tickBlockDelta = getTickBlockDelta(
			periodStartBlock,
			periodEndBlock,
			endBlock,
		);

		// Get emission rate for this period
		const emissionRate =
			i === 0
				? emissionRateChanges[changeBlocks[0]]
				: emissionRateChanges[changeBlocks[i - 1]];

		// Add to accumulated increase
		accumulatedIncrease +=
			(BigInt(emissionRate) * BigInt(tickBlockDelta)) / totalStaked;

		// Move start block forward
		periodStartBlock = periodEndBlock;
	}

	// Process final period
	const finalDelta = getTickBlockDelta(
		periodStartBlock,
		currentBlock,
		endBlock,
	);

	// Get final emission rate
	const finalEmissionRate =
		// periodEndBlock <= currentBlock
		//   ? emissionRateChanges.get(periodEndBlock) // Rate for period that started at periodEndBlock
		//   : emissionRateChanges.get(changeBlocks[i - 1]); // Rate after last processed change block
		BigInt(getEmissionRate());

	// Add final period increase
	accumulatedIncrease +=
		(BigInt(finalEmissionRate) * BigInt(finalDelta)) / totalStaked;

	return accumulatedIncrease;
}

function getEmissionRate() {
	if (currentBlock >= endBlock) {
		return 0n;
	}

	let emissionRate = 0n;
	let len = changeBlocks.length;
	for (let i = lastProcessedChangeBlockIndex; i < len; ++i) {
		if (currentBlock < changeBlocks[i]) {
			break;
		}
		emissionRate = emissionRateChanges.get(changeBlocks[i]);
	}
	return emissionRate;
}

function getTickBlockDelta(from, to, endBlock) {
	if (to < endBlock) {
		return BigInt(to - from);
	} else if (from >= endBlock) {
		return 0n;
	}
	return BigInt(endBlock - from);
}

function stake(sender, amount) {
	// Input validation
	if (amount === 0n) {
		throw new Error("ZeroAmountNotAllowed");
	}

	if (amount > maxVAssetPerStaker) {
		throw new Error("ExceedsMaximumAllowedStakePerUser");
	}

	// Get or create investor record
	let investor = stakers.get(sender) || {
		vAssetAmount: 0n,
		nativeTokenAmount: 0n,
		claimOffset: 0n,
	};

	_tick();

	// Handle existing stake rewards
	if (investor.vAssetAmount > 0n) {
		const claimableProjectTokenAmount =
			investor.vAssetAmount * cumulativeExchangeRate -
			investor.claimOffset;

		if (claimableProjectTokenAmount > 0n) {
			// Transfer project tokens to sender
			// await projectToken.transfer(sender, claimableProjectTokenAmount);
		}
	}

	// Update investor state
	investor.vAssetAmount += amount;

	// Transfer staked tokens from sender
	totalStaked += amount;

	// TODO: Implement native amount increase here

	// Update claim offset
	investor.claimOffset = investor.vAssetAmount * cumulativeExchangeRate;

	// Save updated investor state
	stakers.set(sender, investor);
}

function _tick() {
	if (currentBlock <= tickBlock) {
		return;
	}

	if (totalStaked == 0) {
		tickBlock = currentBlock;
		_updateLastProcessedIndex();
		return;
	}

	cumulativeExchangeRate += _getPendingExchangeRate();
	tickBlock = currentBlock;
	_updateLastProcessedIndex();
}

function _updateLastProcessedIndex() {
	let len = changeBlocks.length;
	for (let i = lastProcessedChangeBlockIndex; i < len; i++) {
		if (changeBlocks[i] > tickBlock) {
			break;
		}
		lastProcessedChangeBlockIndex = i;
	}
}

function main() {
	stakers.set("alice", {
		vAssetAmount: 0n,
		nativeTokenAmount: 0n,
		claimOffset: 0n,
	});
	stakers.set("bob", {
		vAssetAmount: 0n,
		nativeTokenAmount: 0n,
		claimOffset: 0n,
	});

	const aliceStakeBlock = startBlock + 50n;
	setCurrentBlock(aliceStakeBlock);
	console.log("Alice stakes at block: ", aliceStakeBlock);
	aliceStake = 750n * BigInt(1e18);
	stake("alice", aliceStake);
	console.log(
		"Adjusted cumulative exchange after alice stake: ",
		cumulativeExchangeRate,
	);

	console.log("changeBlocks[i] - 1 is: ", changeBlocks[1] - 1n);
	setCurrentBlock(changeBlocks[1] - 1n);
	bobStake = 300n * BigInt(1e18);
	stake("bob", bobStake);
	console.log(
		"Adjusted cumulative exchange after bob stake: ",
		cumulativeExchangeRate,
	);

	setCurrentBlock(endBlock);
}

main();
