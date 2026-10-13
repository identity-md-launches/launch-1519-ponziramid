# Ponziramid (PONZI)

A fixed-supply ERC-20 for Ethereum. The only production contract is
[`src/Ponziramid.sol`](src/Ponziramid.sol).

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `Ponziramid` |
| Name | `Ponziramid` |
| Symbol | `PONZI` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment transaction value | `0` ETH |
| Initial recipient | Immediate deployer, `msg.sender` |

The constructor mints the entire supply once and emits
`Transfer(address(0), msg.sender, 1000000000000000000000000000)`.
There is no initialization transaction and no later mint or burn function.

## Build and test

Run from the repository root with Foundry and Solidity **0.8.26** installed:

```sh
forge build
forge test
forge fmt --check
```

[`foundry.toml`](foundry.toml) pins Solidity 0.8.26, the Cancun EVM target,
optimizer enabled with 200 runs, and `bytecode_hash = "none"`. No FFI or
filesystem permissions are enabled. All Solidity dependencies and their licenses
are ordinary files under `lib/`; no install command, submodule, RPC, environment
variable, or network access is required for the tests. The compiler and Foundry
are toolchain prerequisites, not repository dependencies.

## Behavior and assumptions

The brief specifies a standard transferable token. This implementation uses the
unmodified ERC-20 base from OpenZeppelin Contracts 5.4.0, with only a fixed-supply
constructor added. Exact dependency versions, commits, and source links are in
[`DEPENDENCIES.json`](DEPENDENCIES.json) and [`VENDOR.md`](VENDOR.md).

- Transfers deliver the exact amount, with no tax, fee, rebase, transfer limit,
  lock, address exemption, or recipient callback.
- Zero-amount transfers to a valid recipient succeed and emit `Transfer`.
  Self-transfers preserve the balance and still require sufficient funds.
- Zero-address recipients and spenders are rejected. Insufficient balances and
  allowances revert with ERC-6093 custom errors; failed transactions preserve
  balances and allowances.
- `approve` replaces an allowance. `transferFrom` consumes finite allowances;
  `type(uint256).max` is treated as unlimited and remains unchanged. Delegated
  self-transfers also consume finite allowances. Even the token holder needs
  an allowance when calling `transferFrom` on their own balance.
- `approve` emits `Approval`; `transferFrom` emits `Transfer` but does not emit
  another `Approval` when reducing the allowance, matching the vendored base.
- There is no owner, administrator, pause, blacklist, seizure, rescue, upgrade,
  permit, proxy, oracle, external service, or payable entry point.

The name is metadata only: the contract implements no investment, referral,
redistribution, or yield mechanism.

## Deployment and operational responsibilities

The deployment target is `src/Ponziramid.sol:Ponziramid`. After building, its ABI
and creation/runtime bytecode are in `out/Ponziramid.sol/Ponziramid.json`.
Constructor arguments are empty; no libraries need linking. Deploy the creation
bytecode directly, without a proxy. The constructor makes no external calls and
requires no pre-existing chain contracts.

The intended launch chain is Ethereum (chain ID 1). Through the IdentityMD
factory, the **factory receives all tokens**, because it is the immediate
deployer. The wallet calling that factory receives nothing in the token's
constructor. Direct deployment would instead mint everything to the direct
deployer. This distinction is covered by the CREATE2 factory test.

The IdentityMD launch system is responsible for deployment, manifest generation,
distribution, pool creation, and explorer verification. In this assignment's
launch, the factory subsequently allocates 100,000,000 PONZI to the distributor,
800,000,000 PONZI to pool seeding, and 100,000,000 PONZI to the requester's
remainder recipient. Those transfers and their destination configuration belong
to the external launch process; the token constructor allocates nothing itself
beyond its one mint to the deployer. There are no application contracts or launch
manifest in this project, and no transactions have been broadcast.

Before releasing the deployment, the launch operator should confirm the built
artifact and compiler settings, token metadata, `totalSupply()`, constructor mint
recipient, and subsequent distribution against the launch manifest. The token's
deployer has custody of the initial supply but no continuing privileged powers.

### After launch

There are no setters, configuration values, keepers, or administrative tasks.
Holders control their balances and allowances. Wallets should approve only the
amount they intend to spend, revoke unused approvals, and account for the ERC-20
allowance replacement race: when changing an existing nonzero allowance, first
set it to zero and wait for confirmation before granting the replacement.
An approved spender can use the old allowance before revocation confirms.

Transfers to contracts do not check whether the recipient can return the tokens.
Tokens accidentally sent to this token contract, or other contracts without a
withdrawal mechanism, cannot be rescued by an administrator. Ordinary ETH sends
revert; forcibly received ETH or unrelated tokens have no recovery mechanism.

## Verification and review scope

The delivered suite contains:

- 29 ERC-20 tests, including three fuzz tests at 512 cases each: metadata,
  mint/transfer/approval events, exact amounts, zero and maximum values,
  self-transfers, allowance replacement/revocation, unauthorized spending,
  and atomic rollback after failures.
- Eight deployment/launch-facing tests: CREATE2 recipient and address prediction,
  whole-amount distribution and custody transfers, rejection of mint/admin/burn
  selectors, unrestricted holder transfers, contract recipients, rejection of
  ordinary ETH sends, runtime size, and forbidden opcode inspection.
- Two stateful invariants run together for 128 sequences of 64 operations:
  balances and supply conservation, and an independent allowance model across
  successful and failing transfers, approvals, and delegated transfers.

The supplied protected test and pinned security reference were reviewed.
The local launch-facing tests exercise token-side custody flows, not Uniswap
pricing or swaps. The full protected v4 harness depends on the separate launch
infrastructure, manifest values, and launch-time addresses and is run by the
independent verifier; it was not executed as part of this project.

Local verification passed with Foundry 1.8.3 and Solidity 0.8.26:
`forge build`, `forge test`, and `forge fmt --check`. A separate clean-copy check
also builds and tests offline with an empty process environment. The current
Foundry version groups the two invariants as one test result (38 total results).

Source review confirmed that minting is constructor-only, the external mutation
surface consists of ERC-20 transfers and approvals, and token operations make no
external calls. Oracle, signature, proxy, and randomness failure modes do not
apply to this implementation. Slither and Mythril were not available and were
not run. This local review and testing do not replace the independent adversarial
review before release.
