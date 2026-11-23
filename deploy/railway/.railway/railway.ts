// Added by the Monad fork on 2026-11-23. See ../README.md.
import {
  defineRailway,
  empty,
  postgres,
  preserve,
  project,
  service,
} from "railway/iac";

// Railway's reference syntax; it fills these in per environment.
const DEVNET_PROXY = "${{devnet-proxy.RAILWAY_PRIVATE_DOMAIN}}";
const PUBLIC_HOST = "${{gateway.RAILWAY_PUBLIC_DOMAIN}}";

export default defineRailway(() => {
  const db = postgres("postgres");

  // Private. The backend's only route to the devnet node, which is on Tailscale.
  const devnetProxy = service("devnet-proxy", {
    source: empty(),
    healthcheck: "/health",
    variables: {
      PORT: "8545",
      // A reusable, ephemeral Tailscale auth key; set in the dashboard, kept by apply.
      TS_AUTHKEY: preserve(),
    },
    // start.sh exits when tailscaled or Caddy does; restart it every time.
    deploy: { restartPolicyType: "ALWAYS" },
  });

  // Private. Indexer and API in one process.
  const backend = service("backend", {
    source: empty(),
    build: { builder: "DOCKERFILE", dockerfilePath: "docker/Dockerfile" },
    start:
      "sh -c 'bin/blockscout eval \"Elixir.Explorer.ReleaseTasks.create_and_migrate()\" && bin/blockscout start'",
    healthcheck: "/api/health/liveness",
    variables: {
      PORT: "4000",
      // Read by the Dockerfile at build time.
      RELEASE_VERSION: "12.0.4",
      DATABASE_URL: db.env.DATABASE_URL,
      ECTO_SSL_MODE: "disable",
      // Set once with the CLI (README.md); kept by apply.
      SECRET_KEY_BASE: preserve(),
      BLOCKSCOUT_HOST: PUBLIC_HOST,
      BLOCKSCOUT_PROTOCOL: "https",
      DISABLE_FILE_LOGGING: "true",
      DISABLE_MARKET: "true",

      ETHEREUM_JSONRPC_VARIANT: "geth",
      ETHEREUM_JSONRPC_TRANSPORT: "http",
      ETHEREUM_JSONRPC_HTTP_URL: `http://${DEVNET_PROXY}:8545/`,
      ETHEREUM_JSONRPC_TRACE_URL: `http://${DEVNET_PROXY}:8545/`,
      ETHEREUM_JSONRPC_WS_URL: `ws://${DEVNET_PROXY}:8546/`,
      CHAIN_ID: "20143",
      COIN: "MON",
      COIN_NAME: "MON",

      // The same indexer settings as docker-compose/monad-devnet.yml, for the same reasons.
      ETHEREUM_JSONRPC_RECEIPTS_BY_BLOCK: "true",
      ETHEREUM_JSONRPC_GETH_TRACE_BY_BLOCK: "true",
      ETHEREUM_JSONRPC_DISABLE_ARCHIVE_BALANCES: "true",
      INDEXER_DISABLE_PENDING_TRANSACTIONS_FETCHER: "true",
      INDEXER_DISABLE_BLOCK_REWARD_FETCHER: "true",
      INDEXER_CATCHUP_BLOCKS_CONCURRENCY: "1",
      INDEXER_CATCHUP_BLOCKS_BATCH_SIZE: "500",
      INDEXER_INTERNAL_TRANSACTIONS_CONCURRENCY: "1",

      // None of the microservices run here.
      MICROSERVICE_SC_VERIFIER_ENABLED: "false",
      MICROSERVICE_VISUALIZE_SOL2UML_ENABLED: "false",
      MICROSERVICE_SIG_PROVIDER_ENABLED: "false",
      NFT_MEDIA_HANDLER_ENABLED: "false",
    },
  });

  // Private. Uploaded from a checkout of the frontend fork, whose Dockerfile is at its root.
  const frontend = service("frontend", {
    source: empty(),
    healthcheck: "/api/healthz",
    variables: {
      PORT: "3000",
      NEXT_PUBLIC_APP_HOST: PUBLIC_HOST,
      NEXT_PUBLIC_APP_PROTOCOL: "https",
      NEXT_PUBLIC_API_HOST: PUBLIC_HOST,
      NEXT_PUBLIC_API_PROTOCOL: "https",
      NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL: "wss",
      NEXT_PUBLIC_API_BASE_PATH: "/",
      NEXT_PUBLIC_NETWORK_NAME: "Monad Devnet",
      NEXT_PUBLIC_NETWORK_SHORT_NAME: "Monad Devnet",
      NEXT_PUBLIC_NETWORK_ID: "20143",
      NEXT_PUBLIC_NETWORK_CURRENCY_NAME: "MON",
      NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL: "MON",
      NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS: "18",
      NEXT_PUBLIC_IS_TESTNET: "true",
      NEXT_PUBLIC_HOMEPAGE_CHARTS: "[]",
      NEXT_PUBLIC_AD_BANNER_PROVIDER: "none",
      NEXT_PUBLIC_AD_TEXT_PROVIDER: "none",
    },
  });

  // The only public service: routes to the backend or the frontend by path.
  const gateway = service("gateway", {
    source: empty(),
    healthcheck: "/health",
    variables: {
      PORT: "8080",
      BACKEND_URL: "http://${{backend.RAILWAY_PRIVATE_DOMAIN}}:4000",
      FRONTEND_URL: "http://${{frontend.RAILWAY_PRIVATE_DOMAIN}}:3000",
    },
  });

  return project("monad-universal-tx-explorer", {
    resources: [db, devnetProxy, backend, frontend, gateway],
  });
});
