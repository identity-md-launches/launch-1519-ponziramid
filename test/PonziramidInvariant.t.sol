// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount;
        if (amountSeed % 4 == 0) amount = type(uint256).max;
        else if (amountSeed % 4 != 1) amount = amountSeed % (SUPPLY + 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
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
        }
    }

    function _amount(uint256 seed, uint256 available) private pure returns (uint256) {
        // Include overdrafts, zero amounts, full balances, and arbitrary valid amounts.
        if (seed % 5 == 0) return available + 1;
        if (seed % 5 == 1) return 0;
        if (seed % 5 == 2) return available;
        return seed % (available + 1);
    }
}

contract PonziramidInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    PonziramidHandler private handler;
    Ponziramid private token;

    function setUp() public {
        handler = new PonziramidHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
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
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
