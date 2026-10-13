// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ponziramid} from "../src/Ponziramid.sol";

/// @dev Tracks an independent balance/allowance model across successful and failing operations.
contract PonziramidHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    Ponziramid public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new Ponziramid();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            require(token.transfer(actors[i], SUPPLY / actors.length));
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        bool expectedSuccess = amount <= expectedBalance[from];
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, expectedSuccess, "transfer success disagrees with model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        } else {
            assertEq(
                result,
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount
                ),
                "overdraft must fail with the balance error"
            );
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount;
        if (amountSeed % 4 == 0) amount = type(uint256).max;
        else if (amountSeed % 4 == 2) amount = type(uint256).max - 1;
        else if (amountSeed % 4 == 3) amount = bound(amountSeed, 0, SUPPLY);
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < allowance ? expectedBalance[owner] : allowance;
        uint256 amount = _amount(amountSeed, available);
        bool expectedSuccess = amount <= available;
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(success, expectedSuccess, "transferFrom success disagrees with model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
            if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        } else if (amount > allowance) {
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount),
                "unauthorized spend must fail with the allowance error"
            );
        } else {
            assertEq(
                result,
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
                ),
                "approved overdraft must fail with the balance error"
            );
        }
    }

    /// @dev Always moves a positive amount between distinct actors, even after balances concentrate.
    function spendApproved(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool infinite)
        external
    {
        uint256 ownerIndex = ownerSeed % actors.length;
        for (uint256 i; i < actors.length && expectedBalance[actors[ownerIndex]] == 0; ++i) {
            ownerIndex = (ownerIndex + 1) % actors.length;
        }
        address owner = actors[ownerIndex];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[(ownerIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = bound(amountSeed, 1, expectedBalance[owner]);
        uint256 approved = infinite ? type(uint256).max : amount;
        _approve(owner, spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        expectedAllowance[owner][spender] = infinite ? type(uint256).max : 0;
    }

    /// @dev Exercises rollback after allowance validation, not merely missing-approval reverts.
    function rejectDelegatedOverdraft(uint256 ownerSeed, uint256 spenderSeed, uint256 excessSeed, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[(ownerSeed % actors.length + 1) % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + bound(excessSeed, 1, type(uint256).max - balance);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // No balance or allowance ghost update: both invariants must still match after the revert.
    }

    function rejectInvalidAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        if (operation % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amountSeed);
        } else if (operation % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _amount(uint256 seed, uint256 available) private pure returns (uint256) {
        // available is at most SUPPLY, so its successor cannot overflow.
        if (seed % 8 == 0) return available + 1;
        if (seed % 8 == 1) return 0;
        if (seed % 8 == 2) return 1;
        if (seed % 8 == 3) return available;
        if (seed % 8 == 4) return type(uint256).max;
        return bound(seed, 0, available);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PonziramidInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    PonziramidHandler private handler;
    Ponziramid private token;

    function setUp() public {
        handler = new PonziramidHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.spendApproved.selector;
        selectors[4] = handler.rejectDelegatedOverdraft.selector;
        selectors[5] = handler.rejectInvalidAddress.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.name(), "Ponziramid");
        assertEq(token.symbol(), "PONZI");
        assertEq(token.decimals(), 18);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
        }
    }

    /// @dev After every random sequence all holders must still be able to spend their entire balances.
    function afterInvariant() public {
        address recipient = makeAddr("post-sequence recipient");
        assertEq(token.balanceOf(recipient), 0);
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = handler.expectedBalance(actor);
            vm.prank(actor);
            assertTrue(token.transfer(recipient, balance));
            assertEq(token.balanceOf(actor), 0);
        }
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        invariant_AllowancesMatchModel();
    }

    /// @dev Exercises successful moves and each new rejection path without relying on random selection.
    function test_HandlerExercisesPositiveSpendsAndRejections() public {
        handler.transfer(0, 1, 2); // one wei
        invariant_SupplyAndBalancesMatchModel();
        handler.approve(1, 2, 0); // infinite allowance
        handler.transferFrom(2, 1, 3, 3); // spend the full available balance
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
        handler.transfer(1, 0, 4); // maximum overdraft from an empty holder
        handler.transferFrom(2, 0, 3, 2); // no approval
        handler.spendApproved(0, 1, 0, 1, false);
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
        handler.spendApproved(3, 2, 0, SUPPLY, true);
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
        handler.rejectDelegatedOverdraft(0, 1, 1, false);
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
        handler.rejectDelegatedOverdraft(3, 2, type(uint256).max, true);
        invariant_SupplyAndBalancesMatchModel();
        invariant_AllowancesMatchModel();
        for (uint8 operation; operation < 3; ++operation) {
            handler.rejectInvalidAddress(0, 1, 1, operation);
            invariant_SupplyAndBalancesMatchModel();
            invariant_AllowancesMatchModel();
        }
        afterInvariant();
    }
}
