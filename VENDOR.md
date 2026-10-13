# Vendored dependencies

All listed files are unmodified upstream sources. Only the source subsets below
and their licenses are included; no Git submodules, package manager downloads,
compiler binaries, upstream tests, or upstream build configuration are required.

| Dependency | Pinned release | Commit | Included files |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0) | `v5.4.0` | `c64a1edb67b6e3f4a15cca8909c9482ad33a02b0` | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors, MIT license |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/`, MIT and Apache-2.0 licenses; test dependency only |

Machine-readable provenance is in [DEPENDENCIES.json](DEPENDENCIES.json).
Files were obtained from GitHub source archives at the listed commits. The
remappings in [remappings.txt](remappings.txt) resolve exclusively inside `lib/`.

OpenZeppelin retains its [MIT license](lib/openzeppelin-contracts/LICENSE).
Forge Standard Library retains its [MIT](lib/forge-std/LICENSE-MIT) and
[Apache-2.0](lib/forge-std/LICENSE-APACHE) licenses.
