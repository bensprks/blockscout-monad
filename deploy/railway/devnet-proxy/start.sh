#!/bin/sh
# Added by the Monad fork on 2026-11-23. See ../README.md.
#
# Runs tailscaled (through containerboot) and Caddy side by side. When either stops, the
# container exits and the platform starts both again.
set -eu

: "${TS_AUTHKEY:?set TS_AUTHKEY to a Tailscale auth key}"
: "${DEVNET_RPC_HTTP_UPSTREAM:?set DEVNET_RPC_HTTP_UPSTREAM to the node's HTTP JSON-RPC address}"
: "${DEVNET_RPC_WS_UPSTREAM:?set DEVNET_RPC_WS_UPSTREAM to the node's WebSocket address, as https://}"

/usr/local/bin/containerboot &
tailscale=$!
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
caddy=$!

trap 'kill "$tailscale" "$caddy" 2>/dev/null; exit 0' TERM INT

while kill -0 "$tailscale" 2>/dev/null && kill -0 "$caddy" 2>/dev/null; do
	sleep 5
done

kill "$tailscale" "$caddy" 2>/dev/null || true
exit 1
