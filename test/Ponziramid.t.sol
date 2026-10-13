// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ponziramid} from "../src/Ponziramid.sol";

/// forge-config: default.fuzz.runs = 1000
contract PonziramidTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    Ponziramid private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new Ponziramid();
    }

    function test_MetadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "Ponziramid");
        assertEq(token.symbol(), "PONZI");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_ConstructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), deployer, SUPPLY);
        vm.prank(deployer);
        new Ponziramid();
    }

    function test_TransferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 123 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireBalanceCanMoveRepeatedly() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_TransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
    }

    function test_TransferMoreThanBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_SelfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_MaximumTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.startPrank(deployer);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertTrue(token.approve(spender, 5 ether));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 5 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_ApproveToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_ApprovalDoesNotRequireTokens() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 60 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 60 ether));
        assertEq(token.allowance(deployer, spender), 40 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 60 ether);
        assertEq(token.balanceOf(alice), 60 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 40 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(bob), 40 ether);
    }

    function test_InfiniteAllowanceIsPreserved() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, alice, 10 ether));
        assertTrue(token.transferFrom(deployer, bob, 20 ether));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 20 ether);
    }

    function test_RevokeApprovalPreventsFurtherSpending() public {
        vm.startPrank(deployer);
        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ApprovalCannotBeUsedByAnotherSpender() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 100 ether);
    }

    function test_TransferFromInsufficientAllowanceRollsBack() public {
        vm.prank(deployer);
        token.approve(spender, 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5 ether, 6 ether)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, 6 ether);
        assertEq(token.allowance(deployer, spender), 5 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 100 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.allowance(alice, spender), 100 ether);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRestoresAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.allowance(deployer, spender), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_TransferFromZeroSenderRevertsEvenForZeroAmount() public {
        // Allowance validation rejects the zero owner before the transfer is reached.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedSelfTransferSpendsAllowanceButPreservesBalance() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_OwnerUsingTransferFromAlsoNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    function testFuzz_TransfersConserveSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferAccounting(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.allowance(deployer, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdraftAlwaysReverts(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        vm.prank(deployer);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OneWeiAllowanceCannotBeSpentTwice() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(deployer, spender), 0);

        // The owner still has tokens: only the exhausted approval prevents replay.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsDecremented() public {
        uint256 approved = type(uint256).max - 1;
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), approved - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_InfiniteApprovalDoesNotPermitMaximumOverdraft() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfApprovedOwnerCanTransferEntireSupply() public {
        vm.startPrank(deployer);
        assertTrue(token.approve(deployer, SUPPLY));
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        vm.stopPrank();
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedOverdraftPreservesApproval(uint256 balance, uint256 excess, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        uint256 amount = balance + excess;
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(deployer);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        // Approval is sufficient, so this reaches balance validation after spending allowance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowancePreservesFundedBalances(uint256 amount, uint256 approved) public {
        amount = bound(amount, 1, SUPPLY);
        approved = bound(approved, 0, amount - 1);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidRecipientPreservesApproval(uint256 amount, uint256 approved, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        approved = infinite ? type(uint256).max : bound(approved, amount, type(uint256).max - 1);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReapprovalAfterPartialSpendReplacesRemainingAllowance(
        uint256 approved,
        uint256 spent,
        uint256 replacement
    ) public {
        approved = bound(approved, 2, SUPPLY / 2);
        spent = bound(spent, 1, approved - 1);
        replacement = bound(replacement, 0, SUPPLY / 2);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, spent));
        assertEq(token.allowance(deployer, spender), approved - spent);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, replacement);
        vm.prank(deployer);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.balanceOf(deployer), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, replacement + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, replacement + 1);
        assertEq(token.allowance(deployer, spender), replacement);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, replacement));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - spent - replacement);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(bob), replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripPreservesBalancesAndApprovals(uint256 funding, uint256 amount, uint256 approved)
        public
    {
        funding = bound(funding, 1, SUPPLY);
        amount = bound(amount, 1, funding);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(bob);
        assertTrue(token.approve(spender, approved));

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), funding - amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - funding);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(bob, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
