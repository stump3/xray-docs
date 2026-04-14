# ReverseProxy (bridge → portal)

Pattern for servers that have **no direct inbound internet connection** — the internal server reaches out to a public portal, which clients then connect to.

```
Client ──── VMESS/SS ──→ Portal (public IP)
                              ↑
                         VMESS/SS (outbound)
                              │
                           Bridge (private/NAT server)
```

## Use cases

- Server behind NAT without port forwarding
- Corporate network with outbound-only firewall
- Double-hop architecture for extra anonymity
- Home server reaching out through a cloud relay

## Variants

| Folder | Transport | Notes |
|---|---|---|
| `Vmess-TCP/` | VMess + TCP | Minimal example |
| `VLESS-TCP-XTLS-WS/` | VLESS+XTLS or WS | Fallback-based, two client modes |
| `Shadowsocks-2022/` | SS 2022 | Pre-shared key auth |

## Files in each variant

- `bridge.jsonc` — config for the **internal server** (no public IP). Connects outward to portal.
- `portal.jsonc` — config for the **public relay**. Accepts both bridge and client connections.
- `client.jsonc` — config for the **end user**. Connects to portal.

## Shadowsocks 2022 key generation

| Cipher | Key length |
|---|---|
| `2022-blake3-aes-128-gcm` | 16 bytes |
| `2022-blake3-aes-256-gcm` | 32 bytes |
| `2022-blake3-chacha20-poly1305` | 32 bytes |

```bash
openssl rand -base64 16   # 128-bit
openssl rand -base64 32   # 256-bit
```

## Notes

- Bridge initiates the connection — no inbound port needed on the bridge side.
- Portal needs a public IP with open ports for both clients and the bridge.
- VLESS+XTLS-WS variant: portal routing can split traffic between bridge (internal network) and direct (internet) by destination IP.
