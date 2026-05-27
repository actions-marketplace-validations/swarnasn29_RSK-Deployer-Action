# Bug Resolution Report — Rootstock Foundry Deployer Action

_Audit of 18 reported findings. Status as of current codebase._

---

## ✅ Resolved

| # | Bug | Solution |
|---|-----|----------|
| 1 | **`bc` not installed in Docker** | `bc` is installed via `apt-get install -y jq bash curl bc` in `Dockerfile`. |
| 2 | **Balance check silently bypassed when `bc` missing** | `bc` is present, so the bypass path (`\|\| echo "1"`) is never hit. Balance check works correctly. |
| 3 | **`apt-get` vs `apk`** | Not a real bug — `ghcr.io/foundry-rs/foundry` is Debian-based, not Alpine. `apt-get` works correctly. Confirmed by successful Docker builds. |
| 4 | **`contract_name` input non-functional** | `entrypoint.sh` correctly appends `--target-contract "$CONTRACT_NAME"` to the forge command when the input is set. |
| 5 | **`exit 0` when broadcast log missing** | `entrypoint.sh` correctly calls `exit 1` when the broadcast log is not found. |
| 6 | **No retry logic for RPC calls** | `cast chain-id`, `cast gas-price`, and `cast balance` all use a 3-retry loop with a 2-second delay. |
| 7 | **`test-local.sh` outputs file not pre-created** | `touch "$DUMMY_DIR/outputs.txt"` is called before `docker run` to ensure Docker mounts a file, not a directory. |
| 8 | **No input validation** | `rpc_url`, `gas_estimate_multiplier`, `min_balance`, and `verifier_type` are all validated with regex/format checks and produce clear error messages on failure. |
| 9 | **`extra_args` flag injection** | `entrypoint.sh` rejects `extra_args` containing `--private-key`, `--rpc-url`, or `--legacy` with a clear error. |
| 10 | **Container runs as root** | `Dockerfile` installs packages as `root`, then switches to `USER foundry` before running the entrypoint. |
| 11 | **Dry-run misses `explorer_url`** | `test-local.sh` validates all four outputs: `contract_address`, `transaction_hash`, `chain_id`, and `explorer_url`. |
| 12 | **`$GITHUB_STEP_SUMMARY` not used** | `entrypoint.sh` writes a Markdown deployment summary to `$GITHUB_STEP_SUMMARY` on success. |
| 13 | **Variable typo `GGAS_GWEI`** | No such typo exists in the current code. Variable is correctly named `GAS_GWEI`. |
| 14 | **Test script uses manual `Vm` interface** | `test-local.sh` uses `import {Script} from "forge-std/Script.sol"` with `vm.startBroadcast()` / `vm.stopBroadcast()`. |
| 15 | **No `--private-key` passed to `forge script`** _(session fix)_ | Replaced `--sender` with `--private-key "$INPUT_PRIVATE_KEY"`. Forge requires an explicit key to sign broadcast transactions. |
| 16 | **Wrong Blockscout verifier URL** _(session fix)_ | Updated `EXPLORER_API` to `rootstock.blockscout.com/api` and `rootstock-testnet.blockscout.com/api` — the actual Blockscout API backends, not the frontend domains. |
| 17 | **Broadcast path strips `.sol` extension** _(session fix)_ | Removed the `%.*` suffix strip. Foundry uses the full filename (`Counter.s.sol`) as the broadcast directory, not a stripped version (`Counter.s`). |
| 18 | **Docker image unpinned (`nightly`)** | Changed base image from `ghcr.io/foundry-rs/foundry:nightly` to `ghcr.io/foundry-rs/foundry:latest` for build stability. |

---

## ⚠️ Accepted / Documented Trade-off

| # | Bug | Status |
|---|-----|--------|
| 19 | **Private key exposed in process arguments** | **Accepted/Documented**: `forge script --broadcast` requires the `--private-key` flag or a local keystore to sign transactions. It does NOT pick up `ETH_PRIVATE_KEY` automatically for signing broadcasted transactions without user-side script modifications. The security risk is mitigated by GitHub Actions' built-in secret masking in logs and the ephemeral nature of the CI container. |
| 20 | **Example workflow misleading comment** | Fixed: comment now accurately states that pushes to `main` use the testnet RPC by default (since `workflow_dispatch` inputs are not available on `push` events). |

---

## 🔒 Security Audit — Round 2 Resolutions (2026-04-10)

_All 8 findings from the second peer-review were addressed. Severity levels: HIGH (H), MEDIUM (M), LOW (L)._

| ID | Severity | Finding | Resolution | Files Changed |
|----|----------|---------|------------|--------------|
| H-1 | HIGH | **Unversioned Docker Base Image (Supply Chain Risk)** — `FROM ghcr.io/foundry-rs/foundry:latest` pulls a mutable tag | Pinned to an immutable SHA-256 digest: `FROM ghcr.io/foundry-rs/foundry:latest@sha256:89a052af62c612d0e05d2596f03edba77d7d904c4478b387a5dc6305821fe0a1`. Added a pinning policy comment in the `Dockerfile` header documenting how to update the digest. | `Dockerfile`, `README.md` |
| H-2 | HIGH | **Command Injection via `extra_args` word-splitting** — `# shellcheck disable=SC2206` allowed unquoted expansion of `$EXTRA_ARGS`; blocklist was easily bypassed | Replaced the unquoted expansion with `IFS=' ' read -ra _raw_tokens <<< "$EXTRA_ARGS"` (safe word splitting). Each token is now validated against a shell metacharacter blocklist (`;`, `\|`, `&`, `$`, backtick, `<`, `>`) before being added to the command array. Forbidden flags (`--private-key`, `--rpc-url`, `--legacy`) are checked per-token via a `case` statement. | `src/entrypoint.sh` |
| M-1 | MEDIUM | **No Path Traversal Validation on `script_path`** — input passed directly to `forge script` without checking for `..` segments | Added a `..` substring check before invoking forge. Additionally performs a `realpath -m` resolution against `$GITHUB_WORKSPACE` when available and aborts if the path escapes the workspace directory. | `src/entrypoint.sh` |
| M-2 | MEDIUM | **`GITHUB_OUTPUT` Injection Risk** — simple `key=value` format is vulnerable to newline/`=` injection | Replaced all `echo "key=value"` writes with the GitHub-recommended heredoc delimiter syntax using `printf 'key<<_EOF_DELIM_\n%s\n_EOF_DELIM_\n'` to fully isolate multi-line values. | `src/entrypoint.sh` |
| M-3 | MEDIUM | **`contract_name` Not Validated as Solidity Identifier** — a crafted value could inject additional forge flags | Added a strict regex validation `^[a-zA-Z_][a-zA-Z0-9_]*$` against `$CONTRACT_NAME` before the forge command is constructed. Invalid names produce a clear error message. | `src/entrypoint.sh` |
| M-4 | MEDIUM | **RPC URL Accepts Any HTTP(S) Endpoint (SSRF Surface)** — only `http://`/`https://` prefix checked; internal network probing possible on self-hosted runners | Added a clear SSRF documentation comment in `entrypoint.sh`. Updated `README.md` with a dedicated "self-hosted runner SSRF notice" section recommending network egress allowlisting and storing the RPC URL in a GitHub Secret. The chain-ID check (must be 30 or 31) provides a hard stop after the first RPC call. | `src/entrypoint.sh`, `README.md` |
| L-1 | LOW | **Gas Price Sanity Check Advisory Only** — action warned but continued even when gas price was below Rootstock's minimum | Added a new `strict_gas_check` input (default: `false`). When set to `true`, the action exits with code 1 when gas price is below the minimum instead of warning and continuing. Documented in `action.yml` and `README.md`. | `src/entrypoint.sh`, `action.yml`, `README.md` |
| L-2 | LOW | **Hardcoded `--etherscan-api-key "none"`** — `"none"` is Blockscout-specific; would silently fail or confuse users with `verifier_type: etherscan` | The `--etherscan-api-key "none"` is now only passed when `$VERIFIER_TYPE == "blockscout"`. When `verifier_type: etherscan`, the new `etherscan_api_key` input is required (validated at startup) and passed as the real key. Setting `verifier_type: etherscan` without providing `etherscan_api_key` now fails fast with a clear error. | `src/entrypoint.sh`, `action.yml`, `README.md` |

---

## 🔒 Security Audit — Round 3 Resolutions (2026-05-27)

_All 10 findings (N-1 through N-10) from the third peer review were addressed. Severity tags: VULN MED, BUG MED, VULN LOW, SMELL LOW, IMPROVE LOW, INFO._

| ID | Severity | Finding | Resolution | Files Changed |
|----|----------|---------|------------|--------------|
| N-1 | VULN MED | **`extra_args` denylist incomplete** — `--verifier-url`, `--keystore`, `--mnemonic`, `--unlocked`, `--fork-url`, `--ledger`, `--trezor`, `--aws` were not blocked. Forge's "last-flag-wins" semantics meant a caller could override the action's `--verifier-url` with their own and exfiltrate contract source during verification. | Switched from denylist to **allowlist** (per reviewer's primary recommendation). Only `--gas-limit`, `--gas-price`, `--priority-gas-price`, `--with-gas-price`, `--slow`, `--skip-simulation`, `--via-ir`, `--non-interactive`, `--resume`, `--delay`, `--retries`, `--code-size-limit` are accepted as flag tokens. Non-flag tokens (values) pass the metacharacter check only, so `--gas-price 100000000` still works. Stripping `=value` suffix means `--gas-price=100` is matched correctly. | `src/entrypoint.sh`, `README.md` |
| N-2 | BUG MED | **`--etherscan-api-key` gated by `CONTRACT_NAME`** — L-2 startup validation accepted `verifier_type=etherscan` with no `contract_name`, then forge ran without the key and failed with a cryptic verification error. | Hoisted the `--etherscan-api-key` block out of the `if [[ -n "$CONTRACT_NAME" ]]` conditional. The key is now appended whenever `VERIFY=true`, regardless of whether `contract_name` is set. CI regression guard added in the new anvil workflow (`L-2 / N-2 regression guard`). | `src/entrypoint.sh` |
| N-3 | BUG MED | **`test-local.sh` dead assertions** — `grep "contract_address="` could never match the new M-2 heredoc output format. | Replaced raw `grep` lines with a heredoc-aware `assert_output` shell function that matches `^${key}<<_EOF_DELIM_$` then verifies the following value line is non-empty. | `test-local.sh` |
| N-4 | VULN LOW | **`bc` receives unvalidated RPC-derived values** — `CURRENT_GAS_PRICE` and `RAW_BALANCE` flowed into `bc` without prior numeric validation. Theoretical defence-in-depth gap. | Added `^[0-9]+$` regex validation immediately after both `cast` retry loops. A non-numeric value now aborts with a clear error instead of silently feeding `bc`. | `src/entrypoint.sh` |
| N-5 | SMELL LOW | **Misleading tokenizer comment** — claimed "respecting quoting boundaries" but `read -ra` does not honour shell quoting. | Rewrote the comment to describe the tokenizer accurately: splits on whitespace, then rejects metacharacters and non-allowlisted flags. Also documents why we deliberately don't honour shell quoting (would require `eval`). | `src/entrypoint.sh` |
| N-6 | SMELL LOW | **Path traversal check fires after 3 RPC calls** — wasted user network resources when the input was structurally invalid. | Moved the M-1 traversal/realpath checks from the deployment step up into the early input validation block, alongside `contract_name` and `verifier_type` validation. All static input validation now completes before any `cast chain-id` / `cast gas-price` / `cast balance` call. | `src/entrypoint.sh` |
| N-7 | SMELL LOW | **`examples/deploy-example.yml` missing new inputs** — users didn't see how to wire `strict_gas_check` or `etherscan_api_key`. | Added commented-out `strict_gas_check`, `verifier_type: 'etherscan'`, and `etherscan_api_key` blocks to the example, each with a short note on when to enable them. | `examples/deploy-example.yml` |
| N-8 | IMPROVE LOW | **`test-local.sh` uses `set -e` only** — unset-variable and pipefail traps were disabled, masking potential test regressions. | Upgraded to `set -euo pipefail` for parity with production `entrypoint.sh`. Guarded the `TEST_PRIVATE_KEY` check with `${TEST_PRIVATE_KEY:-}` so the new `-u` rule doesn't trip when the variable is unset. | `test-local.sh` |
| N-9 | INFO | **`ws` transitive vulnerabilities (GHSA-58qx-3vcg-4xpx)** | **Not applicable** to this action. The repository ships only a Dockerfile, Bash entrypoint, and YAML configuration — there is no `package.json`, no `node_modules`, and no JS/TS source tree. The reviewer's note appears to reference a sibling repo; documented here so future reviewers do not re-flag. | _none_ |
| N-10 | INFO / GAP | **No Anvil-backed integration test** across two prior cycles. | Added `.github/workflows/anvil-integration.yml`. It starts `anvil --chain-id 31`, bootstraps a minimal Foundry project, then drives the container directly with three scenarios: (a) **positive**: deploy with `verify: false` and assert all four heredoc outputs match strict regex patterns (covers M-2 output format, full broadcast→jq pipeline, M-1 realpath branch via `GITHUB_WORKSPACE`); (b) **L-2/N-2 regression guard**: `verifier_type=etherscan` without `etherscan_api_key` and without `contract_name` must abort with the documented error; (c) **M-1/N-6 traversal guard**: `script_path: '../etc/passwd'` must abort before any RPC call. Required a new `verify` action input (default `true`, backwards-compatible) so the test can deploy against anvil without --verify failing against a Blockscout endpoint that doesn't know about the local node. | `.github/workflows/anvil-integration.yml`, `action.yml`, `src/entrypoint.sh`, `README.md` |

### Related new feature

| Input | Default | Purpose |
|-------|---------|---------|
| `verify` | `true` | New action input introduced to unblock N-10. When `false`, the action omits `--verify`, `--verifier`, `--verifier-url`, and `--etherscan-api-key` from the forge invocation. The L-2 startup check for `etherscan_api_key` is gated on `VERIFY=true` so `verifier_type=etherscan` + `verify=false` is now a valid combination (no key required). |

### Side fix surfaced during local test execution

| File | Change | Why |
|------|--------|-----|
| `Dockerfile` | Refreshed the H-1 base-image digest pin from `sha256:89a052af…fe0a1` (2026-04-10) to `sha256:8347b728…3a19cdd` (2026-05-27). | The previous pin had been garbage-collected from `ghcr.io/foundry-rs/foundry:latest`, so `docker build` failed with `failed to resolve source metadata`. The new digest is the current multi-arch OCI index digest reported by `docker buildx imagetools inspect`. Pinning policy documented in the Dockerfile header is unchanged. |

---
