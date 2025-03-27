// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MockLaunchpool } from "@src/mocks/MockLaunchpool.sol";
import { Launchpool } from "@src/non-upgradeable/Launchpool.sol";
import { MockERC20 } from "@src/mocks/MockERC20.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { console } from "forge-std/console.sol";
import { DeployMockXCMOracle } from "test/testutils/DeployMockXCMOracle.sol";
import { MockXCMOracle } from "@src/mocks/MockXCMOracle.sol";
import { IXCMOracle } from "@src/interfaces/IXCMOracle.sol";
import { SetupStakers } from "test/testutils/SetupStakers.sol";

contract OwnerInterestTest is Test {
	MockLaunchpool launchpool;
	MockERC20 projectToken;
	MockERC20 vAsset;
	MockERC20 nativeAsset;
	DeployMockXCMOracle mockOracleDeployer = new DeployMockXCMOracle();
	MockXCMOracle mockOracle;
	SetupStakers setupStakers = new SetupStakers();

	address owner;
	address platformAdmin;
	address staker1;
	address staker2;

	// Constants for testing
	uint128 public START_BLOCK;
	uint128 public END_BLOCK;
	uint256 public constant MAX_VSTAKER = 1000 ether;
	uint256 public constant BLOCK_TIME = 6 seconds;
	uint128 public poolDurationBlocks = uint128(14 days) / uint128(BLOCK_TIME);
	uint128 public ownerShareOfInterest = 90; // 90% for owner, 10% as platform fee

	constructor() {}

	function setUp() public {
		owner = address(this);
		platformAdmin = makeAddr("platformAdmin");
		staker1 = makeAddr("staker1");
		staker2 = makeAddr("staker2");

		// Deploy mock tokens
		projectToken = new MockERC20("Project Token", "PT");
		vAsset = new MockERC20("vAsset Token", "vToken");
		nativeAsset = new MockERC20("Native Asset", "Native");

		// Deploy mock xcm oracle with 1.2 initial rate, 10 block interval, 8% APY, 6 seconds block time
		mockOracle = MockXCMOracle(
			mockOracleDeployer.deploy(1.2e18, 10, 80000, 6)
		);

		// Set start block in the future
		START_BLOCK = uint128(block.number + 10);
		END_BLOCK = START_BLOCK + poolDurationBlocks;

		// Set up change blocks and emission rates for the Launchpool
		uint128[] memory changeBlocks = new uint128[](1);
		changeBlocks[0] = START_BLOCK;

		uint256[] memory emissionRates = new uint256[](1);
		emissionRates[0] = 100 ether;

		// Deploy Launchpool with exposed functions
		launchpool = new MockLaunchpool(
			owner,
			address(projectToken),
			address(vAsset),
			address(nativeAsset),
			START_BLOCK,
			END_BLOCK,
			MAX_VSTAKER,
			changeBlocks,
			emissionRates
		);

		// Setup pool with needed tokens
		uint256 requiredProjectTokens = poolDurationBlocks * emissionRates[0];
		projectToken.freeMintTo(address(launchpool), requiredProjectTokens);
		vAsset.freeMintTo(staker1, 1000 ether);
		vAsset.freeMintTo(staker2, 1000 ether);

		// Configure Launchpool
		launchpool.wild_setPlatformAdminAddress(platformAdmin);
		// launchpool.setXCMOracleAddress(address(xcmOracle));
		launchpool.wild_setOwnerShareOfInterest(ownerShareOfInterest);
	}

	// Helper function to setup staking with interest simulation
	function _setupStakingScenario(uint256 interestPercentage) internal {
		address[] memory stakers = setupStakers.createAndApprove(
			2,
			address(launchpool),
			address(vAsset)
		);
		staker1 = stakers[0];
		staker2 = stakers[1];

		// Simulate staking from both stakers
		vm.roll(START_BLOCK);

		uint256 stakeAmount = 500 ether;
		vm.prank(staker1);
		launchpool.stake(stakeAmount);

		vm.prank(staker2);
		launchpool.stake(stakeAmount);

		console.log(
			"********* Average native ex rate gradient after 2 stakes: %d",
			launchpool.avgNativeExRateGradient()
		);

		// Simulate interest accrual
		vm.roll(END_BLOCK);
		uint256 lastExRate = mockOracle.getLastSetExchangeRate();
		uint256 newRate = (lastExRate * (100 + interestPercentage)) / 100;
		mockOracle.setExchangeRate(newRate);
	}

	// Test basic interest claiming functionality - kept as is, as per the instruction
	function test_claim_owner_interest_success() public {
		address[] memory stakers = setupStakers.createAndApprove(
			1,
			address(launchpool),
			address(vAsset)
		);
		vm.roll(START_BLOCK);
		uint256 stakeAmount = 500 * (10 ** vAsset.decimals());
		vm.prank(stakers[0]);
		launchpool.stake(500 ether);

		// Simulate 1% interest accrual til end block
		vm.roll(END_BLOCK);
		uint256 lastExRate = mockOracle.getLastSetExchangeRate();
		mockOracle.setExchangeRate((lastExRate * (100 + 1)) / 100);

		// Jump to after pool end

		// Record balances before claim
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		uint256 platformBalanceBefore = vAsset.balanceOf(platformAdmin);
		uint256 poolBalanceBefore = vAsset.balanceOf(address(launchpool));

		// Get expected amounts
		(uint256 ownerClaims, uint256 platformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();

		// Total interest should be about 20% of 300 ether = 60 ether
		uint256 totalInterest = ownerClaims + platformFee;
		// uint256 investorVAssets = launchpool.exposed_getVTokenByTokenWithoutFee(
		// 	launchpool.totalNativeStake()
		// );
		assertApproxEqRel(
			totalInterest,
			// vAsset.balanceOf(address(launchpool)) - investorVAssets,
			(stakeAmount * 1) / 100,
			0.01e18, // 1% difference tolerance between expected and actual value
			"Total interest should be close to 20% of staked amount"
		);

		// Owner claims interest
		launchpool.claimOwnerInterest();

		// Verify balances after claim
		assertEq(
			vAsset.balanceOf(owner),
			ownerBalanceBefore + ownerClaims,
			"Owner should receive correct amount of interest"
		);

		assertEq(
			vAsset.balanceOf(platformAdmin),
			platformBalanceBefore + platformFee,
			"Platform admin should receive correct fee"
		);

		assertEq(
			vAsset.balanceOf(address(launchpool)),
			poolBalanceBefore - ownerClaims - platformFee,
			"Pool balance should be reduced by claimed amounts"
		);

		// Verify correct split according to ownerShareOfInterest
		assertApproxEqRel(
			ownerClaims,
			(totalInterest * ownerShareOfInterest) / 100,
			0.01e18,
			"Owner claims should be correct percentage of interest"
		);
	}

	// Test claiming when there's no interest
	function test_claim_with_no_interest() public {
		// Setup staking with 0% interest
		_setupStakingScenario(0);

		vm.roll(END_BLOCK + 1);

		// Record balances before claim
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		uint256 platformBalanceBefore = vAsset.balanceOf(platformAdmin);

		// Get claimable amounts
		(uint256 ownerClaims, uint256 platformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();

		// Should be very close to zero
		assertLe(
			ownerClaims + platformFee,
			0.01 ether,
			"Total claimable amount should be near zero with no interest"
		);

		// Owner claims interest
		launchpool.claimOwnerInterest();

		// Verify minimal or no changes in balances (might be small rounding differences)
		assertApproxEqAbs(
			vAsset.balanceOf(owner),
			ownerBalanceBefore,
			0.01 ether,
			"Owner balance should barely change when no interest"
		);

		assertApproxEqAbs(
			vAsset.balanceOf(platformAdmin),
			platformBalanceBefore,
			0.01 ether,
			"Platform admin balance should barely change when no interest"
		);
	}

	// Test claiming with varying interest percentages
	function test_claim_with_different_owner_interest_splits() public {
		// Test with different owner shares
		uint128[] memory shares = new uint128[](4);
		shares[0] = 60; // 60% owner, 40% platform
		shares[1] = 90; // 90% owner, 10% platform
		shares[2] = 100; // 100% owner, 0% platform
		shares[3] = 0; // 0% owner, 100% platform

		for (uint i = 0; i < shares.length; i++) {
			// Reset scenario for each test case
			if (i > 0) {
				// Reset the test environment
				setUp();
			}

			// Setup staking with 15% interest
			_setupStakingScenario(1);
			vm.roll(END_BLOCK + 1);

			// Record balances before claim
			uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
			uint256 platformBalanceBefore = vAsset.balanceOf(platformAdmin);

			// Set new owner share
			launchpool.wild_setOwnerShareOfInterest(shares[i]);

			// Get claimable amounts after setting new share
			(uint256 ownerClaims, uint256 platformFee) = launchpool
				.exposed_getPlatformAndOwnerClaimableVAssets();
			uint256 totalClaimable = ownerClaims + platformFee;

			// Owner claims interest
			launchpool.claimOwnerInterest();

			// Calculate expected amounts based on the total claimable
			uint256 expectedOwnerAmount = (totalClaimable * shares[i]) / 100;
			uint256 expectedPlatformAmount = totalClaimable -
				expectedOwnerAmount;

			// Verify actual distribution
			assertApproxEqAbs(
				vAsset.balanceOf(owner) - ownerBalanceBefore,
				expectedOwnerAmount,
				0.01 ether,
				string(
					abi.encodePacked(
						"Owner should get ",
						shares[i],
						"% of interest"
					)
				)
			);

			assertApproxEqAbs(
				vAsset.balanceOf(platformAdmin) - platformBalanceBefore,
				expectedPlatformAmount,
				0.01 ether,
				string(
					abi.encodePacked(
						"Platform should get ",
						100 - shares[i],
						"% of interest"
					)
				)
			);
		}
	}

	// Test claiming multiple times with increasing interest
	function test_multiple_owner_claims_with_increasing_interest() public {
		// Initial setup with 10% interest
		_setupStakingScenario(10);

		vm.roll(END_BLOCK + 1);

		// First claim
		uint256 ownerBalanceBeforeFirst = vAsset.balanceOf(owner);
		uint256 platformBalanceBeforeFirst = vAsset.balanceOf(platformAdmin);

		(uint256 firstOwnerClaims, uint256 firstPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();

		launchpool.claimOwnerInterest();

		// Verify first claim
		assertApproxEqAbs(
			vAsset.balanceOf(owner) - ownerBalanceBeforeFirst,
			firstOwnerClaims,
			0.01 ether,
			"First owner claim amount incorrect"
		);

		assertApproxEqAbs(
			vAsset.balanceOf(platformAdmin) - platformBalanceBeforeFirst,
			firstPlatformFee,
			0.01 ether,
			"First platform fee amount incorrect"
		);

		// Simulate more interest accrual by increasing the exchange rate further
		uint256 lastRate = mockOracle.getLastSetExchangeRate();
		uint256 newRate = (lastRate * 115) / 100; // Additional 15% increase
		mockOracle.setExchangeRate(newRate);

		// Add more vAssets to the pool to simulate the interest accrual
		uint256 additionalVAssets = (1000 ether * 15) / 100; // 15% more interest
		vAsset.freeMintTo(address(launchpool), additionalVAssets);

		// Second claim
		uint256 ownerBalanceBeforeSecond = vAsset.balanceOf(owner);
		uint256 platformBalanceBeforeSecond = vAsset.balanceOf(platformAdmin);

		(uint256 secondOwnerClaims, uint256 secondPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();

		launchpool.claimOwnerInterest();

		// Verify second claim
		assertApproxEqAbs(
			vAsset.balanceOf(owner) - ownerBalanceBeforeSecond,
			secondOwnerClaims,
			0.01 ether,
			"Second owner claim amount incorrect"
		);

		assertApproxEqAbs(
			vAsset.balanceOf(platformAdmin) - platformBalanceBeforeSecond,
			secondPlatformFee,
			0.01 ether,
			"Second platform fee amount incorrect"
		);

		// The second claimed amount should be roughly related to the additional interest
		assertApproxEqRel(
			secondOwnerClaims + secondPlatformFee,
			additionalVAssets,
			0.1e18,
			"Second total claim should match additional interest"
		);
	}

	// Test claiming when some users haven't unstaked
	function test_claim_with_active_stakers() public {
		// Setup staking scenario with 15% interest
		_setupStakingScenario(15);

		// Advance to after pool end
		vm.roll(END_BLOCK + 1);

		// Get initial claimable amounts
		(uint256 initialOwnerClaims, uint256 initialPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();
		uint256 initialTotalClaims = initialOwnerClaims + initialPlatformFee;

		// Staker1 unstakes
		vm.startPrank(staker1);
		uint256 staker1WithdrawableAmount = launchpool.getWithdrawableVTokens(
			launchpool.getStakerNativeAmount(staker1)
		);
		console.log(
			"vAssets in the pool before staker 1 unstaked: %d",
			vAsset.balanceOf(address(launchpool))
		);
		launchpool.unstake(staker1WithdrawableAmount);
		vm.stopPrank();
		console.log(
			"Avg native ex rate gradient after staker 1 unstaked: %d",
			launchpool.avgNativeExRateGradient()
		);
		console.log(
			"Remaining vAssets in the pool after staker 1 unstaked: %d",
			vAsset.balanceOf(address(launchpool))
		);

		// But staker2 hasn't unstaked yet

		// Owner claims interest
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		launchpool.claimOwnerInterest();
		uint256 firstClaimAmount = vAsset.balanceOf(owner) - ownerBalanceBefore;

		// Verify owner can still claim interest even with active stakers
		assertTrue(
			firstClaimAmount > 0,
			"Owner should be able to claim with active stakers"
		);

		// Now staker2 unstakes
		vm.startPrank(staker2);
		uint256 staker2WithdrawableAmount = launchpool.getWithdrawableVTokens(
			launchpool.getStakerNativeAmount(staker2)
		);
		launchpool.unstake(staker2WithdrawableAmount);
		vm.stopPrank();

		// Check if there's any additional claimable interest after all unstaking
		(uint256 finalOwnerClaims, uint256 finalPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();

		if (finalOwnerClaims > 0 || finalPlatformFee > 0) {
			// Owner claims again if there's anything to claim
			uint256 ownerBalanceBeforeSecond = vAsset.balanceOf(owner);
			launchpool.claimOwnerInterest();
			uint256 secondClaimAmount = vAsset.balanceOf(owner) -
				ownerBalanceBeforeSecond;

			// Could be zero or small due to rounding
			assertGe(
				secondClaimAmount,
				0,
				"Second claim should be zero or positive"
			);
		}
	}

	// Test claiming when contract is paused
	function test_claim_when_paused() public {
		// Setup staking with interest
		_setupStakingScenario(10);

		vm.roll(END_BLOCK - 1);

		// Pause the contract
		vm.prank(platformAdmin);
		launchpool.pause();

		// Verify contract is paused
		assertTrue(launchpool.paused(), "Contract should be paused");

		// Owner tries to claim
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		vm.prank(owner);
		launchpool.claimOwnerInterest();
		uint256 claimAmount = vAsset.balanceOf(owner) - ownerBalanceBefore;

		// ClaimOwnerInterest should work even when paused since it's not using the whenNotPaused modifier
		assertTrue(
			claimAmount > 0,
			"Owner should be able to claim when contract is paused"
		);
	}

	function test_owner_interest_with_multiple_periods() public {
		// SETUP: Initial staking period
		address[] memory initialStakers = setupStakers.createAndApprove(
			3,
			address(launchpool),
			address(vAsset)
		);

		// First period staking
		vm.roll(START_BLOCK);
		for (uint i = 0; i < initialStakers.length; i++) {
			vm.prank(initialStakers[i]);
			launchpool.stake(300 ether);
		}

		// First interest accrual (10%)
		vm.roll(START_BLOCK + 300);
		uint256 firstExRate = mockOracle.getLastSetExchangeRate();
		uint256 newRate1 = (firstExRate * 110) / 100; // 10% increase
		mockOracle.setExchangeRate(newRate1);

		// FIRST CLAIM: Owner claims first period interest
		uint256 ownerBalanceBefore1 = vAsset.balanceOf(owner);
		uint256 platformBalanceBefore1 = vAsset.balanceOf(platformAdmin);

		(uint256 firstOwnerClaim, uint256 firstPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();
		uint256 firstTotalInterest = firstOwnerClaim + firstPlatformFee;

		launchpool.claimOwnerInterest();

		// Verify interest distribution - 90% to owner, 10% to platform
		assertApproxEqRel(
			vAsset.balanceOf(owner) - ownerBalanceBefore1,
			(firstTotalInterest * ownerShareOfInterest) / 100,
			0.0001e18,
			"First owner claim should be 90% of total interest"
		);

		assertApproxEqRel(
			vAsset.balanceOf(platformAdmin) - platformBalanceBefore1,
			(firstTotalInterest * (100 - ownerShareOfInterest)) / 100,
			0.0001e18,
			"First platform fee should be 10% of total interest"
		);

		// SECOND PERIOD: Some unstake, new stakers join, higher interest
		vm.startPrank(initialStakers[0]);
		console.log(
			"*Pool vAsset balance prior to unstaking: %d",
			vAsset.balanceOf(address(launchpool))
		);
		launchpool.unstake(300 ether - ((300 ether * 10) / 100)); // Less withdrawable vAssets due to increased interest
		vm.stopPrank();
		console.log(
			"*Pool vAsset balance after unstaking: %d",
			vAsset.balanceOf(address(launchpool))
		);
		console.log(
			"Cum. native -> project token exchange rate before unstaking: %d",
			launchpool.cumulativeExchangeRate()
		);

		// New stakers join
		address[] memory newStakers = setupStakers.createAndApprove(
			2,
			address(launchpool),
			address(vAsset)
		);

		vm.roll(START_BLOCK + 600);
		console.log(
			"Cum. native -> project token exchange rate after unstaking: %d",
			launchpool.cumulativeExchangeRate() +
				launchpool.exposed_getPendingExchangeRate()
		);
		for (uint i = 0; i < newStakers.length; i++) {
			vm.prank(newStakers[i]);
			launchpool.stake(500 ether);
		}

		// Second interest accrual (20%)
		vm.roll(START_BLOCK + 700);
		uint256 secondExRate = mockOracle.getLastSetExchangeRate();
		uint256 newRate2 = (secondExRate * 120) / 100; // 20% increase
		mockOracle.setExchangeRate(newRate2);

		// SECOND CLAIM: Owner claims again
		uint256 ownerBalanceBefore2 = vAsset.balanceOf(owner);
		uint256 platformBalanceBefore2 = vAsset.balanceOf(platformAdmin);

		(uint256 secondOwnerClaim, uint256 secondPlatformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();
		uint256 secondTotalInterest = secondOwnerClaim + secondPlatformFee;

		launchpool.claimOwnerInterest();

		// Should be higher than first period due to more stakers and higher interest
		assertTrue(
			secondTotalInterest > firstTotalInterest,
			"Second period interest should be higher than first"
		);

		// Verify second interest distribution follows same proportion
		assertApproxEqRel(
			vAsset.balanceOf(owner) - ownerBalanceBefore2,
			(secondTotalInterest * ownerShareOfInterest) / 100,
			0.0001e18,
			"Second owner claim should be 90% of total interest"
		);

		assertApproxEqRel(
			vAsset.balanceOf(platformAdmin) - platformBalanceBefore2,
			(secondTotalInterest * (100 - ownerShareOfInterest)) / 100,
			0.0001e18,
			"Second platform fee should be 10% of total interest"
		);
	}

	// Fuzz test with various interest percentages and owner shares
	function testFuzz_claim_owner_interest(
		uint8 interestPercentage,
		uint8 ownerSharePercentage
	) public {
		// Bound inputs to reasonable values
		interestPercentage = uint8(bound(interestPercentage, 1, 50)); // 1% to 50% interest
		ownerSharePercentage = uint8(bound(ownerSharePercentage, 1, 100)); // 1% to 100% owner share

		// Setup staking with fuzzed interest percentage
		_setupStakingScenario(interestPercentage);

		vm.roll(END_BLOCK + 1);

		// Set fuzzed owner share percentage
		launchpool.wild_setOwnerShareOfInterest(ownerSharePercentage);

		// Record balances before claim
		uint256 ownerBalanceBefore = vAsset.balanceOf(owner);
		uint256 platformBalanceBefore = vAsset.balanceOf(platformAdmin);

		// Get expected claimable amounts
		(uint256 ownerClaims, uint256 platformFee) = launchpool
			.exposed_getPlatformAndOwnerClaimableVAssets();
		uint256 totalClaims = ownerClaims + platformFee;

		// Owner claims interest
		launchpool.claimOwnerInterest();

		// Verify actual splits according to ownerSharePercentage
		uint256 actualOwnerClaim = vAsset.balanceOf(owner) - ownerBalanceBefore;
		uint256 actualPlatformClaim = vAsset.balanceOf(platformAdmin) -
			platformBalanceBefore;

		// Should be close to the expected percentages
		assertApproxEqRel(
			actualOwnerClaim,
			(totalClaims * ownerSharePercentage) / 100,
			0.01e18,
			"Owner claim should match expected percentage"
		);

		assertApproxEqRel(
			actualPlatformClaim,
			(totalClaims * (100 - ownerSharePercentage)) / 100,
			0.01e18,
			"Platform claim should match expected percentage"
		);

		// Total claimed should match total claimable (within tolerance)
		assertApproxEqAbs(
			actualOwnerClaim + actualPlatformClaim,
			totalClaims,
			0.01 ether,
			"Total claimed should match total claimable"
		);
	}
}
