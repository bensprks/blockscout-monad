# Added by the Monad fork on 2026-11-23. See ../README.md.
#
# Joins the tailnet without a TUN device and forwards JSON-RPC to the devnet node, so the
# explorer's backend can reach a node that is only on Tailscale.
FROM caddy:2.11.7-alpine AS caddy

FROM tailscale/tailscale:v1.104.7
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY start.sh /start.sh

# Userspace networking is containerboot's default. State stays in memory: every start
# registers a new ephemeral node.
ENV TS_OUTBOUND_HTTP_PROXY_LISTEN=127.0.0.1:1055 \
    TS_ACCEPT_DNS=true \
    TS_HOSTNAME=explorer-devnet-proxy

ENTRYPOINT ["/start.sh"]
