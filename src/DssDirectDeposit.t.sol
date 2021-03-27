pragma solidity 0.6.12;

import "ds-test/test.sol";
import "dss-interfaces/Interfaces.sol";

import "./DssDirectDeposit.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external view returns (bytes32);
}

contract DssDirectDepositTest is DSTest {

    uint256 constant RAY = 10 ** 27;

    Hevm hevm;

    DssDirectDeposit deposit;
    LendingPoolLike pool;
    InterestRateStrategyLike interestStrategy;
    DaiAbstract dai;
    DSTokenAbstract adai;

    function setUp() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256('hevm cheat code'))))));

        deposit = new DssDirectDeposit();
        pool = LendingPoolLike(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        adai = DSTokenAbstract(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
        dai = DaiAbstract(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        interestStrategy = InterestRateStrategyLike(0xfffE32106A68aA3eD39CcCE673B646423EEaB62a);

        // Mint ourselves 100B DAI
        giveTokens(DSTokenAbstract(address(dai)), 100_000_000_000 ether);

        dai.approve(address(pool), uint256(-1));
    }

    function giveTokens(DSTokenAbstract token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (token.balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                address(token),
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                address(token),
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (token.balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    address(token),
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    function calculateLiquidityRequiredForTargetInterestRate(uint256 interestRate) public returns (uint256) {
        require(interestRate <= interestStrategy.variableRateSlope2(), "above-max-interest");

        // Do inverse calc
        uint256 supplyAmount = adai.totalSupply();
        uint256 borrowAmount = supplyAmount - dai.balanceOf(address(adai));
        log_named_decimal_uint("supplyAmount", supplyAmount, 18);
        log_named_decimal_uint("borrowAmount", borrowAmount, 18);
        uint256 targetUtil;
        if (interestRate > interestStrategy.variableRateSlope1()) {
            // Excess interest rate
            targetUtil = (interestRate - interestStrategy.baseVariableBorrowRate() - interestStrategy.variableRateSlope1()) * interestStrategy.OPTIMAL_UTILIZATION_RATE() * interestStrategy.EXCESS_UTILIZATION_RATE() / interestStrategy.variableRateSlope2() / RAY + interestStrategy.OPTIMAL_UTILIZATION_RATE();
        } else {
            // Optimal interst rate
            targetUtil = (interestRate - interestStrategy.baseVariableBorrowRate()) * interestStrategy.OPTIMAL_UTILIZATION_RATE() / interestStrategy.variableRateSlope1();
        }
        log_named_decimal_uint("targetUtil", targetUtil, 27);
        uint256 targetSupply = borrowAmount * RAY / targetUtil;
        log_named_decimal_uint("targetSupply", targetSupply, 18);
        return targetSupply;
    }

    function test_set_aave_interest_rate() public {
        (,,,, uint256 borrowRate,,,,,,,) = pool.getReserveData(address(dai));
        log_named_decimal_uint("origBorrowRate", borrowRate, 27);

        uint256 supplyAmount = adai.totalSupply();
        uint256 targetSupply = calculateLiquidityRequiredForTargetInterestRate(1 * RAY / 100);

        if (targetSupply > supplyAmount) {
            pool.deposit(address(dai), targetSupply - supplyAmount, address(this), 0);
        } else if (targetSupply < supplyAmount) {
            // Withdraw
        }

        (,,,, borrowRate,,,,,,,) = pool.getReserveData(address(dai));
        log_named_decimal_uint("newBorrowRate", borrowRate, 27);

        log_named_decimal_uint("adai", adai.balanceOf(address(this)), 18);

        assertTrue(false);
    }
    
}
