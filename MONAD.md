# Monad universal transaction support

Added by the Monad fork on 2026-11-20.

This is a private fork of Blockscout used as a reference for what a block explorer has to change to
support Monad's universal transaction type (`0x40`). It tracks the protocol in phases; only phase 0
is implemented.

| Repository | Upstream | Base |
| --- | --- | --- |
| `bensprks/blockscout-monad` (this one) | `blockscout/blockscout` | `v12.0.4` |
| `bensprks/blockscout-frontend-monad` | `blockscout/frontend` | `v2.13.0` |

The protocol is specified in the "Universal Transaction Type" Notion page. The node implementation
is in `category-labs/monad-bft#3352` and `category-labs/monad#2840`.

## Phase 0: what an explorer has to change

In phase 0 a type `0x40` transaction carries the same information as an EIP-1559 transaction. The
node returns the usual JSON-RPC transaction and receipt fields, with `"type": "0x40"`.

For an explorer that indexes over JSON-RPC, as Blockscout does, that means:

| Area | Change needed | Why |
| --- | --- | --- |
| Indexer | None | `EthereumJSONRPC.Transaction` parses `type` as a quantity, and `Explorer.Chain.Transaction` stores it as an integer with no whitelist. |
| Hashes and senders | None | `hash` and `from` are taken from the RPC response. Blockscout never decodes raw transaction bytes or recovers the sender. |
| Fees | None | Fee display depends on `maxFeePerGas`, `maxPriorityFeePerGas` and the receipt, not on the type number. |
| API | None | API v2 returns `type` as the stored integer (`64`). |
| UI | One label | The frontend prints the raw type number with a name for types 2, 3 and 4 only. |

The semantic badge in transaction lists ("Coin transfer", "Contract call", and so on) is left
alone on purpose. A universal transaction is still one of those things, and the badge should keep
saying which.

Explorers that parse raw blocks or raw transactions do have work to do in phase 0: they need the
`0x40 || rlp([chain_id, features])` decoding and the five-field receipt. Blockscout is not one of
them.

### Changes in this fork

- `docker-compose/monad-devnet.yml`: a profile for the type `0x40` devnet (chain 20143).
- `docker-compose/proxy/explorer.conf.template`: larger header buffers, without which browsers
  get a 502 from the proxy.
- Frontend fork: "Txn type: 64" is shown as "Txn type: 64 (Universal, 0x40)".

There is no `monad` chain type yet. A chain type exists to hold extra columns and parsing, and
phase 0 has neither.

### Verified on the devnet

Checked on 2026-11-23 against the shared devnet (chain 20143, node
`Monad/v0.12.2-rc-593-ga05418d5`), with the stack from `docker-compose/monad-devnet.yml`:

- Blocks containing type `0x40` transactions import with no backend code change, and API v2
  returns `"type": 64` for them.
- The transaction page renders "Txn type: 64 (Universal, 0x40)".
- `eth_getBlockReceipts` and `debug_traceBlockByNumber` (with `callTracer`) return what the `geth`
  variant expects.
- `apps/ethereum_jsonrpc` has parser tests built from the devnet's transaction and receipt
  responses.

What this does not cover: every transaction the indexer had seen on the devnet was a plain value
transfer between accounts. Contract creation, call data, logs, access lists and failed
transactions of type `0x40` have not been exercised.

Compared with a type `0x2` transaction object from the same node, a type `0x40` one has no
`accessList` key (type `0x2` returns `[]`). Blockscout does not read that key.

## Running against the devnet

Check out both forks side by side, then:

```bash
cd docker-compose
docker compose -f monad-devnet.yml up --build -d
```

The explorer is served at http://localhost. The node endpoints, chain id and frontend checkout
path can be overridden from the shell; the variables are listed at the top of
`monad-devnet.yml`.

The devnet is only reachable over Tailscale. With Colima on macOS, containers reach it through
the host's Tailscale connection with no extra setup.

A full sync of the devnet (about 1.4 million blocks, nearly all empty) takes between one and two hours.
Catch-up runs from the chain tip downwards, so the oldest transactions appear last.

## Node behaviour that affects indexers

Seen on the devnet node on 2026-11-23. Worth raising with the node team before an explorer team
finds it.

When requests overlap, the node answers `"result": null` for blocks that exist. With ten batches
of ten requests in flight, 36 to 64 of 500 `eth_getBlockByNumber` calls and 145 of 500
`eth_getBlockReceipts` calls came back `null`; one batch at a time, none of 50 did. Under the same
load `debug_traceBlockByNumber` fails with `-32602 Block requested not found`.

Blockscout treats `null` as a missing block and retries, so it converges, but with its default
catch-up settings (ten concurrent batches of ten) most batches failed and the sync crawled. The
devnet profile therefore fetches one batch of 500 blocks at a time, which ran at roughly 170 to
270 blocks per second with no failed batches. An indexer that reads `null` as "this block does not
exist" would silently skip blocks: a one-off scan of `eth_getBlockTransactionCountByNumber` with
four requests in flight missed three of the five transactions in one range.

## Responses that would stall the indexer

Blockscout drops unknown JSON keys, but it is strict about a few known ones. From reading the
import path, a block containing a transaction or receipt like the following fails to import, and
the indexer keeps retrying it rather than skipping the transaction:

- `value`, `gas` or `nonce` as JSON `null` (use `0x0`).
- `input` as JSON `null` (use `0x`).
- `authorizationList` as JSON `null` (omit it or use `[]`).
- `r` or `s` missing from the transaction object (`0x0` is accepted).
- A receipt `status` other than `0x0` or `0x1`.

The specification's JSON-RPC section already uses `0x0`, `0x` and `[]` for absent values. These
become relevant once transactions without an ECDSA signature or without a single call exist.

## Later phases

Nothing below is implemented. It records where the work will land.

| Feature | RPC change in the specification | Explorer work |
| --- | --- | --- |
| Batch calls | `calls: [{to, value, input}]`; `to`, `value` and `input` nulled when there is not exactly one call | New column, parsing, API field and UI. Address and balance indexing must follow each call, not only `to`. |
| Fee sponsorship | `feePayer` on the transaction | New column, API field and UI. Fee attribution moves from `from` to the payer. |
| Ordering and storage charges | `fee` on the receipt; `gasUsed` becomes gas charged | New receipt column, and fee display must use `fee` instead of `gasUsed × effectiveGasPrice`. No upstream precedent. |
| Encrypted transactions | Decrypted values appear in the existing fields | None expected for an RPC-based explorer. |

Upstream already supports a transaction type with the same `calls` and `feePayer` JSON shape: the
`eden` chain type, added in `blockscout/blockscout#14643`. When batch calls or sponsorship reach
the devnet, add a `monad` chain type modelled on it rather than designing one from scratch. The
frontend renders `fee_payer` and `calls` whenever the API returns them.

A view of the raw feature map, decoded from `debug_getRawTransaction`, would need a type `0x40`
codec in the frontend. Use the `viem/monad` module from `haythemsellami/viem#1`, vendored the way
the Rabby fork does it, instead of writing a second one.

## Keeping up with upstream

`master` (here) and `main` (frontend) mirror upstream. `monad` is the default branch and carries
the fork's commits on top of an upstream release tag.

```bash
git fetch upstream --tags
git rebase --onto <new-tag> <old-tag> monad
```

GitHub Actions is disabled on both forks, since upstream's workflows are not meant to run here.

## Licence

Blockscout releases from v11.0.0 (backend) are under the Blockscout Software Licence, not GPL-3.
For this fork that means:

- It is for internal use. Do not give the modified code, or images built from it, to third
  parties without a commercial licence from Blockscout.
- Modified files carry a notice with the date of modification.
- The "Made with Blockscout" footer stays.

This document describes protocol impact and can be shared separately from the code.
