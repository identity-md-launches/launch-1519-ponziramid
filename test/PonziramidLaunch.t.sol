// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ponziramid} from "../src/Ponziramid.sol";

/// @dev Test-only factory. No deployed launch infrastructure or network access is needed.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (Ponziramid) {
        return new Ponziramid{salt: salt}();
    }

    function move(Ponziramid token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// @dev A transfer to a contract must not call its fallback or require receiver registration.
contract RejectingReceiver {
    fallback() external {
        revert("no callbacks accepted");
    }
}

contract PonziramidLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    TokenFactoryHarness private factory;
    Ponziramid private token;
    address private launcher;
    address private holder;
    address private recipient;

    function setUp() public {
        launcher = makeAddr("launcher");
        holder = makeAddr("holder");
        recipient = makeAddr("recipient");
        factory = new TokenFactoryHarness();
        vm.prank(launcher, launcher);
        token = factory.deploy(keccak256("launch"));
    }

    function test_Create2MintsEverythingToImmediateFactory() public view {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            keccak256("launch"),
                            keccak256(type(Ponziramid).creationCode)
                        )
                    )
                )
            )
        );
        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(launcher), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_DistributionAndPoolCustodyTransfersArriveWhole() public {
        address distributor = makeAddr("distributor");
        address poolCustodian = makeAddr("pool custodian");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        factory.move(token, distributor, SUPPLY / 10);
        factory.move(token, poolCustodian, SUPPLY * 8 / 10);
        factory.move(token, recipient, SUPPLY / 10);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(poolCustodian), SUPPLY * 8 / 10);
        assertEq(token.balanceOf(recipient), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, SUPPLY / 10));
        assertEq(token.balanceOf(claimant), SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);

        // Token-side custody flows only; the protected harness exercises the actual v4 swaps.
        vm.prank(poolCustodian);
        assertTrue(token.transfer(trader, 100 ether));
        assertEq(token.balanceOf(trader), 100 ether);
        vm.prank(trader);
        assertTrue(token.transfer(poolCustodian, 100 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolCustodian), SUPPLY * 8 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintInitializeOrUpgradeEntryPointsForAnyone() public {
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", holder, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("initialize(address)", holder);
        calls[5] = abi.encodeWithSignature("setMinter(address)", holder);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", holder);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", holder);

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(holder);
            (bool outsiderSuccess,) = address(token).call(calls[i]);
            assertFalse(outsiderSuccess);
            vm.prank(address(factory));
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(factory)), SUPPLY);
            assertEq(token.balanceOf(holder), 0);
        }
    }

    function test_FactoryCannotFreezeBurnOrSeizeHolderTokens() public {
        factory.move(token, holder, 1_000 ether);
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("pause()");
        calls[1] = abi.encodeWithSignature("blacklist(address)", holder);
        calls[2] = abi.encodeWithSignature("freeze(address)", holder);
        calls[3] = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        calls[4] = abi.encodeWithSignature("lock(address)", holder);
        calls[5] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[6] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1_000 ether);
        calls[7] = abi.encodeWithSignature("seize(address)", holder);

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(address(factory));
            (bool success,) = address(token).call(calls[i]);
            assertFalse(success);
            assertEq(token.balanceOf(holder), 1_000 ether);
        }
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        vm.prank(address(factory));
        token.transferFrom(holder, recipient, 1);

        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1_000 ether));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_HolderCannotBurnSupply() public {
        factory.move(token, holder, 100 ether);
        vm.prank(holder);
        (bool success,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 100 ether));
        assertFalse(success);
        assertEq(token.balanceOf(holder), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransfersToContractsDoNotMakeCallbacks() public {
        RejectingReceiver receiver = new RejectingReceiver();
        factory.move(token, address(receiver), 100 ether);
        assertEq(token.balanceOf(address(receiver)), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(holder, 1 ether);
        vm.prank(holder);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
    }

    function test_RuntimeIsDeployableAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
