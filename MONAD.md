# Monad universal transaction support

Added by the Monad fork on 2026-11-20.

This is a fork of Blockscout used as a reference for what a block explorer has to change to
support Monad's universal transaction type (`0x40`). It tracks the protocol in phases: phase 0 and
batch calls are implemented.

| Repository | Upstream | Base |
| --- | --- | --- |
| `bensprks/blockscout-monad` (this one) | `blockscout/blockscout` | `v12.0.4` |
| `bensprks/blockscout-frontend-monad` | `blockscout/frontend` | `v2.13.0` |

The node implementation is in `category-labs/monad-bft#3352` and `category-labs/monad#2840`. The
protocol specification is not public yet: what this document says about later phases comes from
that specification and may change.

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
- `docker-compose/monad-devnet.host.yml`: overrides for running that profile on a shared host.
- `docker-compose/proxy/explorer.conf.template`: larger header buffers, without which browsers
  get a 502 from the proxy.
- Frontend fork: "Txn type: 64" is shown as "Txn type: 64 (Universal, 0x40)".

Phase 0 itself needs no chain type: it has no extra columns or parsing. Batch calls do; see
"Batch calls" below.

### Verified on the devnet

Checked on 2026-11-23 against the devnet (chain 20143, node
`Monad/v0.12.2-rc-593-ga05418d5`), with the stack from `docker-compose/monad-devnet.yml`:

- Blocks containing type `0x40` transactions import with no backend code change, and API v2
  returns `"type": 64` for them.
- The transaction page renders "Txn type: 64 (Universal, 0x40)".
- `eth_getBlockReceipts` and `debug_traceBlockByNumber` (with `callTracer`) return what the `geth`
  variant expects.
- `apps/ethereum_jsonrpc` has parser tests built from the devnet's transaction and receipt
  responses.

A full sync imported 1,379,726 blocks with no gaps and 18 transactions: 17 of type `0x40` and
one of type `0x2`, all successful.

What this does not cover: all 18 are plain value transfers between accounts. Contract creation,
call data, logs, access lists and failed transactions of type `0x40` have not been exercised.

Compared with a type `0x2` transaction object from the same node, a type `0x40` one has no
`accessList` key (type `0x2` returns `[]`). Blockscout does not read that key.

## Batch calls

Since 2026-11-25 the devnet node (`Monad/v0.12.2-rc-594`) returns a `calls` array on every type
`0x40` transaction, next to `accessList` and `authorizationList`:

```json
"to": null, "value": "0x0", "input": "0x",
"calls": [
  { "to": null, "value": "0x0", "input": "0x6014…" },
  { "to": "0xe69a…b667", "value": "0x0", "input": "0x…01" }
]
```

With exactly one call, `to`, `value` and `input` repeat that call. Otherwise the node sets them to
`null`, `0x0` and `0x`. The receipt is unchanged; when a call creates a contract, its
`contractAddress` is set.

`debug_traceTransaction` with `callTracer` returns a single-call transaction as one frame, as for
any other type. A batch comes back as a root frame from the sender to itself, with no value or
input, and one child frame per call.

### What an unmodified explorer shows

Blockscout keeps importing these blocks, but it drops `calls` and reads the empty `to` as a
contract creation. Every batch is labelled "Contract creation", the transaction page shows no
recipients, values or call data, and the addresses a batch calls do not list it. The calls are
visible only as internal transactions, one per child frame.

### What this fork changes

The fork adds a `monad` chain type. Everything it does is listed here, so the same list is the
work for any explorer built like Blockscout.

| Area | Change | Where |
| --- | --- | --- |
| Chain type | `CHAIN_TYPE=monad` and its repo are registered | `config/config_helper.exs`, `Explorer.Repo`, the repo lists under `config/` |
| Storage | A nullable `calls` column (`jsonb`) on `transactions` | `apps/explorer/priv/monad/migrations`, `Explorer.Chain.Transaction` |
| Parsing | `calls` is read, with each `value` as an integer. For a batch, `to` and `input` are taken from the first call and `value` is the sum over all calls | `EthereumJSONRPC.Transaction` |
| Import | `calls` is written, and updated when a block is fetched again | `Explorer.Chain.Import.Runner.Transactions` |
| Addresses | The recipient of every call gets an address row | `Indexer.Transform.Addresses` |
| Balances | The State tab moves the value of a batch once, through its internal transactions | `Explorer.Chain.Transaction.StateChange` |
| API | API v2 returns `calls` for a single transaction, and `null` in lists | `BlockScoutWeb.API.V2.MonadView`, the transaction schema |
| UI | None needed: the frontend draws a "Calls" table and lists the recipients under "To" whenever the API returns `calls`. One hint that said "sponsored" was reworded | frontend fork |

Three of these are decisions, not consequences:

- **`to` of a batch is its first call.** The node reports `null`. Leaving it would keep the
  "Contract creation" label and would leave the batch out of every address's transaction list.
  The first call is the convention upstream's `eden` chain type uses for its batches. A batch
  whose first call creates a contract is therefore still a contract creation, with its address.
- **`value` of a batch is the sum of its calls.** It is what the sender sends in total.
- **The value of a batch is not applied at the transaction level.** On Monad each call of a batch
  is also an internal transaction from the sender, so applying the transaction's `to` and `value`
  as well would count the value twice. Upstream's `eden` code does the opposite, because Eden's
  batched calls are not traced.

Upstream's `eden` chain type has the same `calls` shape and was the model. It is not reused
directly: it would bring Eden's fee payer handling and its balance rule, and tie the fork to
changes made for another chain. The address step and the API schema of a call are shared with it.

A chain type is chosen at compile time, so `CHAIN_TYPE` is a build argument and must be set to the
same value at run time. The devnet profile does both. Blocks imported before the switch keep
their old rows until they are fetched again. Blockscout does that for blocks marked with
`refetch_needed` whose numbers are in `missing_block_ranges`; `Explorer.Chain.Block.set_refetch_needed/1`
does both.

### Limits

- An address that is called by a batch, but not by its first call, does not list the batch under
  its transactions. It does list the call under its internal transactions.
- List badges follow the first call, so a batch reads as "Contract call" or "Coin transfer". There
  is no "batch" badge.
- The frontend shows the "Calls" table only after "View details" is clicked.
- No batch on the devnet moves value yet. The balance rule is covered by tests, not by live data.
- A transaction with an empty `calls` array is left as the node reports it.

## Running against the devnet

Check out both forks side by side, then give the profile a node and start it:

```bash
cd docker-compose
export MONAD_RPC_HTTP_URL=https://<node>:<http port>/
export MONAD_RPC_WS_URL=wss://<node>:<ws port>/
docker compose -f monad-devnet.yml up --build -d
```

The explorer is served at http://localhost. The two endpoints can also go in a `.env` file next to
`monad-devnet.yml`. The chain id and the frontend checkout path have defaults that can be
overridden; they are listed at the top of that file.

The devnet node is not public: it is reachable only over a private Tailscale network. With Colima
on macOS, containers reach it through the host's Tailscale connection with no extra setup.

A full sync of the devnet (about 1.4 million blocks, nearly all empty) takes about two hours.
Catch-up runs from the chain tip downwards, so the oldest transactions appear last.

Restart the backend once block import has finished. The trace queue is in memory and by then
holds millions of empty blocks; after a restart it is rebuilt from the blocks that have
transactions, and their internal transactions appear within a minute or two.

### On a host shared with other workloads

`docker-compose/monad-devnet.host.yml` is a set of overrides for running the explorer next to
something that must not be disturbed, such as the node itself. It publishes only the explorer,
on one address and port, gives every service a CPU and a memory limit (about 2.7 cores and 8 GB
in total), and expects the two images to be built beforehand.

```bash
# Build under whatever limit the host needs. With systemd, for example:
systemd-run --user --scope -p CPUQuota=300% -p Nice=19 \
  docker build -t blockscout-monad-backend:local --build-arg RELEASE_VERSION=12.0.4 \
  --build-arg CHAIN_TYPE=monad \
  -f docker/Dockerfile .
# and the same for blockscout-monad-frontend:local, from the frontend checkout.

cd docker-compose
docker compose -f monad-devnet.yml -f monad-devnet.host.yml up -d
```

Set `EXPLORER_BIND` to the one address the explorer should listen on, and `EXPLORER_HOST` and
`EXPLORER_PORT` to what browsers will use to reach it. The default is `127.0.0.1:8090`. Do not
bind it to every interface on a host with a public address: published container ports bypass
most host firewalls.

It has been run this way with rootless Podman 5.7 behind `docker compose`. Three things differ
from Docker there, and the overrides handle them: container links are refused, an empty volume
takes the image's ownership on every start, and so Postgres has to run as the image's own user.
Two more are left to the operator: enable lingering for the user (`loginctl enable-linger`) and
the `podman-restart` user service, or the containers stop at logout and stay down after a
reboot.

Following the tip, the whole stack used about 0.4 of a core and 1.3 GB of memory. After the
backend container is recreated, restart the `proxy` container: nginx keeps the old address.

To skip the initial sync, load a dump of an already synced database into the `db` container
before the backend first starts.

## Node behaviour that affects indexers

Seen on the devnet node (`Monad/v0.12.2-rc-593-ga05418d5`) on 2026-11-23. That is a pre-release
build, so this may not hold for later ones.

When requests overlap, the node answers `"result": null` for blocks that exist. With ten batches
of ten requests in flight, 36 to 64 of 500 `eth_getBlockByNumber` calls and 145 of 500
`eth_getBlockReceipts` calls came back `null`; one batch at a time, none of 50 did. Under the same
load `debug_traceBlockByNumber` fails with `-32602 Block requested not found`.

Blockscout treats `null` as a missing block and retries, so it converges, but with its default
catch-up settings (ten concurrent batches of ten) most batches failed and the sync crawled. The
devnet profile therefore fetches one batch of 500 blocks at a time. Over five minutes that
imported about 226 blocks per second, with 5 of 137 batches failing and retried.

Traces stay in batches of ten. Blockscout requests a trace for every block, empty or not, and
with batches of 500 those requests overlapped block import for long enough that the failures came
back and the sync fell to about 47 blocks per second. In small batches traces lag behind block
import, so the internal transactions of old blocks arrive hours after the blocks do.

An indexer that reads `null` as "this block does not exist" would silently skip blocks: a one-off
scan of `eth_getBlockTransactionCountByNumber` with four requests in flight missed three of the
five transactions in one range.

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

Apart from batch calls, nothing below is implemented. It records where the work will land.

| Feature | RPC change in the specification | Explorer work |
| --- | --- | --- |
| Batch calls | `calls: [{to, value, input}]`; `to`, `value` and `input` nulled when there is not exactly one call | Done; see "Batch calls" above. |
| Fee sponsorship | `feePayer` on the transaction | New column, API field and UI. Fee attribution moves from `from` to the payer. |
| Ordering and storage charges | `fee` on the receipt; `gasUsed` becomes gas charged | New receipt column, and fee display must use `fee` instead of `gasUsed × effectiveGasPrice`. No upstream precedent. |
| Encrypted transactions | Decrypted values appear in the existing fields | None expected for an RPC-based explorer. |

Upstream's `eden` chain type, added in `blockscout/blockscout#14643`, also carries `feePayer` in
the JSON shape the specification uses. When sponsorship reaches the devnet, extend the `monad`
chain type from that code: a `fee_payer_address_hash` column, the API field, and fee attribution
to the payer. The frontend already renders `fee_payer` whenever the API returns it.

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

Both forks are under the Blockscout Software Licence, as upstream has been since v11.0.0 of the
backend; see `LICENSE`. It is not GPL-3. Anyone who uses this code is bound by that licence,
including its limits on commercial use and on distributing modified versions.

In these forks:

- Modified files carry a notice with the date of modification.
- The "Made with Blockscout" footer stays.

The forks are not affiliated with or endorsed by Blockscout.
