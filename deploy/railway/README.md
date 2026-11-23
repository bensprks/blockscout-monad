# Hosting the explorer on Railway

Added by the Monad fork on 2026-11-23.

Runs the explorer for the type `0x40` devnet in the `category-labs` Railway workspace, behind a
username and password. It follows the demos in `category-labs/category-integrations`, with two
differences: the node is not part of the project, and the services are uploaded from local
checkouts instead of built from GitHub.

| Service | Public | What it is |
| --- | --- | --- |
| `gateway` | Yes | Caddy. Basic Auth on every path but `/health`, then `/api` and `/socket` to the backend and the rest to the frontend. |
| `frontend` | No | The frontend fork. |
| `backend` | No | This repository: indexer and API. |
| `postgres` | No | Railway's Postgres. |
| `devnet-proxy` | No | Joins the tailnet and forwards JSON-RPC to the devnet node, which is only on Tailscale. |

`.railway/railway.ts` describes all of it. The Railway CLI applies it; deploys do not read it.

## Why the services are uploaded

Railway's GitHub app in the `category-labs` workspace cannot see these private forks, and their
code cannot move into `category-integrations`: that repository is GPL-3, and Blockscout's licence
does not allow relicensing. `railway up` uploads a checkout and builds it on Railway, so a deploy
is a command, not a push.

## Requirements

- Railway CLI 5.49 or newer, and a seat in the `category-labs` workspace.
- Checkouts of this repository and of the frontend fork.
- A Tailscale auth key that is reusable and ephemeral. Give it a tag whose ACL allows only the
  devnet node's ports 8080 and 8081; a tagged key also avoids node key expiry. The auth key
  itself still expires (90 days at most), after which a restart of `devnet-proxy` fails until
  the variable holds a new one.

## First-time setup

Run the `railway` commands from `deploy/railway/`.

1. `npm install`, then `railway login`.
2. Create the project and link this folder to its `production` environment:

   ```
   railway init --name monad-universal-tx-explorer --workspace category-labs
   ```

3. `railway config plan`, then `railway config apply`. This creates the database and four empty
   services.
4. Set the values `railway.ts` leaves out. In the dashboard, as sealed variables:
   - `devnet-proxy`: `TS_AUTHKEY`. Until it is set the service restarts in a loop.
   - `gateway`: `BASIC_AUTH_USER`, and `BASIC_AUTH_HASH` from

     ```
     docker run --rm caddy:2.11.7-alpine caddy hash-password --plaintext 'YOUR_PASSWORD'
     ```

     Until both are set every path but `/health` answers 401.

   And the backend's secret, generated and set without ever being shown:

   ```
   openssl rand -base64 64 | tr -d '\n' | railway variables --service backend --set-from-stdin SECRET_KEY_BASE --skip-deploys
   ```
5. `railway domain --service gateway --port 8080` generates the public URL. The frontend reads
   it at start, so do this before the first frontend deploy.
6. Upload the services:

   ```
   railway up devnet-proxy --path-as-root --service devnet-proxy --detach
   railway up gateway --path-as-root --service gateway --detach
   railway up ../.. --path-as-root --service backend --detach
   railway up <frontend checkout> --path-as-root --service frontend --detach
   ```

## Loading an existing index

A fresh database can be filled from one that is already synced, such as the one behind
`docker-compose/monad-devnet.yml`. The explorer then shows the chain as of the dump, and the
indexer carries on from there once `devnet-proxy` is connected.

1. Dump the synced database:

   ```
   docker exec db pg_dump -U blockscout -Fc --no-owner --no-acl blockscout > dump.pgc
   ```

2. `railway down --service backend` so nothing holds the tables.
3. Add a one-off service with `DATABASE_URL` set to `${{postgres.DATABASE_URL}}`, and upload a
   folder holding the dump and a Dockerfile `FROM postgres:17` that runs
   `pg_restore --clean --if-exists --no-owner --no-acl -d "$DATABASE_URL"` on it. The database
   has no public address, so the load has to run inside the project.
4. When its log reports the restore, `railway down` that service and delete it, so it can never
   run again and reset the database. Then upload `backend` again.

## Updating

Run the matching `railway up` line again. Change settings in `.railway/railway.ts`, then
`railway config plan` and `railway config apply`; do not edit them in the dashboard. After a
`railway up`, the plan lists a harmless `source.type` change for that service.

## Notes

- A fresh database syncs the whole devnet from the tip downwards. That takes about two hours,
  and the oldest transactions appear last. Restart `backend` once block import has finished, so
  that traces for the blocks with transactions run first. `MONAD.md` explains both.
- Anyone with the password can read the explorer. Blockscout's licence limits this fork to
  internal use, so keep the password inside the company.
- The explorer does not publish a node RPC URL, so wallets cannot be connected through it.
