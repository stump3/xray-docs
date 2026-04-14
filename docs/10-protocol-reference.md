# 10 — Protocol Reference

Consolidated reference across both upstream repositories: XTLS/Xray-examples and lxhao61/integrated-examples.

---

## Letter codes (lxhao61 notation)

lxhao61 uses single-letter codes in directory names for protocols in composite configurations:

| Letter | Protocol | Transport | Security | CDN | Certificate |
|---|---|---|---|---|---|
| **M** | VLESS + Vision | RAW (TCP) | REALITY | ❌ | ❌ |
| **E** | VLESS + Vision | RAW (TCP) | TLS | ❌ | ✅ |
| **F** | Trojan + RAW | RAW (TCP) | TLS 1.2 + CHACHA20 | ❌ | ✅ |
| **H** | VLESS + XHTTP | XHTTP | TLS (Nginx/Caddy) | ✅ | ✅ |
| **K** | VLESS + XHTTP | XHTTP over REALITY | REALITY (nested via M) | ❌ | ❌ |
| **G** | Shadowsocks + gRPC | gRPC | TLS (Nginx/Caddy) | ✅ | ✅ |
| **C** | VMess + WebSocket | WebSocket | TLS (Nginx/Caddy) | ✅ | ✅ |
| **D** | Trojan + HTTP/2 | H2C | TLS (Caddy) | ✅ | ✅ |
| **A** | VLESS + mKCP | mKCP | seed | ❌ | ❌ |
| **N** | NaiveProxy | HTTP/2 or HTTP/3 | TLS (Caddy ACME) | ✅ | ✅ auto |
| **T** | Trojan-Go | TCP or WebSocket | TLS (Caddy) | ✅ WS | ✅ auto |

> **K (nested)** is not a separate inbound — it reuses the XHTTP inbound from H. A K client connects through M's Reality handshake, then falls back into H's XHTTP sub-inbound. No server-side changes beyond M + H are needed.

---

## All protocols × transports

### VLESS (most combinations, Xray-exclusive features available)

| Transport | Security | CDN | Certificate | Min Xray | Notes |
|---|---|---|---|---|---|
| TCP/RAW | none | ❌ | ❌ | any | Behind reverse proxy with TLS |
| TCP/RAW | TLS | ❌ | ✅ | any | Standard TLS 1.2/1.3 |
| TCP/RAW | TLS + Vision | ❌ | ✅ | ≥ v1.7.2 | Eliminates double-TLS; `flow: xtls-rprx-vision` |
| TCP/RAW | REALITY | ❌ | ❌ | ≥ v1.8.0 | No cert needed; steals target site handshake |
| TCP/RAW | REALITY + Vision | ❌ | ❌ | ≥ v1.8.0 | Maximum concealment |
| WebSocket | TLS | ✅ | ✅ | any | CDN-compatible; aging, being replaced by XHTTP |
| gRPC | TLS | ✅ | ✅ | ≥ v1.4.0 | Nginx `grpc_pass`; CDN-compatible |
| gRPC | REALITY | ❌ | ❌ | ≥ v1.8.0 | Unusual — runs on port 80 in XTLS example |
| HTTP/2 (H2C) | none | ✅ | ✅ | any | Behind Caddy H2C reverse proxy |
| HTTP/3 | TLS (ALPN h3) | ✅ | ✅ | any | Via Caddy QUIC; Nginx QUIC |
| HTTPUpgrade | TLS | ✅ | ✅ | ≥ v1.8.9 | More efficient than WebSocket |
| XHTTP | TLS | ✅ | ✅ | ≥ v24.11.30 | Split upload/download; preferred over WS/gRPC |
| XHTTP | REALITY | ❌ | ❌ | ≥ v24.10.31 | Standalone (K pattern shares H inbound) |
| XHTTP (UDS) | none | ❌ | ❌ | ≥ v24.11.30 | Unix socket → Nginx HTTP/3 |
| mKCP | seed | ❌ | ❌ | any | UDP; separate port; high throughput under loss |

### VMess (V2Ray + Xray compatible)

| Transport | Security | CDN | Certificate | Notes |
|---|---|---|---|---|
| TCP | none | ❌ | ❌ | Basic VMess |
| TCP | TLS | ❌ | ✅ | Standard |
| TCP | HTTP obfuscation | ❌ | ❌ | Deprecated approach |
| WebSocket | none | ✅ | ✅ (on proxy) | Behind TLS-terminating reverse proxy |
| WebSocket | TLS | ✅ | ✅ | CDN-compatible; aging |
| gRPC | TLS | ✅ | ✅ | CDN-compatible |
| HTTP/2 | TLS | ✅ | ✅ | |
| HTTPUpgrade | TLS | ✅ | ✅ | ≥ Xray v1.8.9 |
| XHTTP | TLS | ✅ | ✅ | ≥ Xray v24.11.30 |
| mKCP | seed | ❌ | ❌ | UDP; separate port |

### Trojan (V2Ray + Xray compatible)

| Transport | Security | CDN | Notes |
|---|---|---|---|
| TCP/RAW | TLS | ❌ | Standard Trojan; Xray-client recommended (fingerprint spoofing) |
| TCP/RAW | TLS 1.2 + CHACHA20 | ❌ | F-pattern: non-AES cipher for distinct TLS fingerprint |
| WebSocket | TLS | ✅ | CDN-compatible |
| HTTP/2 (H2C) | TLS | ✅ | Caddy H2C |
| gRPC | TLS | ✅ | Via Nginx/Caddy `grpc_pass` |

> Original Trojan and Trojan-Go clients do not support TLS fingerprint spoofing. Use Xray-client with Trojan protocol.

### Shadowsocks

| Variant | Transport | CDN | Notes |
|---|---|---|---|
| AEAD (aes-256-gcm, chacha20-poly1305) | TCP | ❌ | Classic; V2Ray + Xray |
| 2022-blake3-aes-128/256-gcm | TCP | ❌ | SS 2022; Xray ≥ v1.7.0 only |
| + gRPC + TLS | gRPC | ✅ | SS over gRPC via Nginx/Caddy |
| + WebSocket + TLS (via dokodemo-door) | WebSocket | ✅ | Emulates v2ray-plugin WS mode |

SS 2022 multi-user:
```jsonc
"settings": {
  "method":   "2022-blake3-aes-128-gcm",
  "password": "MASTER-KEY==",
  "clients": [
    { "password": "SUB-KEY-1==", "email": "user1" },
    { "password": "SUB-KEY-2==", "email": "user2" }
  ]
}
// Client connects with: "MASTER-KEY==:SUB-KEY-1=="
```
> `2022-blake3-chacha20-poly1305` does **not** support multi-user. V2Ray does not support SS 2022 at all.

### Third-party (Caddy/standalone)

| Protocol | Transport | CDN | Notes |
|---|---|---|---|
| NaiveProxy | HTTP/2 or HTTP/3 | ✅ | Caddy forwardproxy plugin; passive DPI resistance |
| Trojan-Go | TCP or WebSocket | ✅ WS | caddy-trojan plugin; use TCP mode only (WS lacks 0-RTT) |
| Hysteria v2 | HTTP/3 QUIC (BBR) | ❌ | Salamander obfs optional; optimal under high packet loss |

---

## Version requirements

### Xray-core

| Version | What it unlocks |
|---|---|
| ≥ v1.4.0 | gRPC transport |
| ≥ v1.7.0 | Shadowsocks 2022 |
| ≥ v1.7.2 | XTLS Vision (`xtls-rprx-vision`) |
| ≥ v1.8.0 | REALITY |
| ≥ v1.8.9 | HTTPUpgrade transport |
| ≥ v24.10.31 | XHTTP + REALITY; `target` field (replaces `dest` alias) |
| ≥ v24.11.30 | Full XHTTP with split upload/download streams |
| ≥ v24.12.18 | `fingerprint: "chrome"` is the default — no longer needed explicitly |
| ≥ v25.3.6 | Minimum recommended for new XHTTP+Reality deployments |

### Nginx

| Version | What it unlocks |
|---|---|
| ≥ v1.19.4 | `ssl_reject_handshake` |
| ≥ v1.25.0 | HTTP/3 (QUIC) server |
| ≥ v1.25.1 | H2C + HTTP/1.1 on the same port/process |

### Caddy

| Version | What it unlocks |
|---|---|
| ≥ v2.6.0 | H2C reverse proxy + UDS forwarding |
| ≥ v2.7.0 | PROXY protocol native support |
| ≥ v2.9.0 | HTTP/3 → H2C reverse proxy |
| ≥ v2.9.1 + caddy-l4 | SNI routing (equivalent to Nginx stream) |

### V2Ray (for reference)

| Version | What it unlocks |
|---|---|
| ≥ v4.31.0 | Trojan protocol |
| ≥ v4.36.2 | gRPC transport |
| ≥ v4.37.0 | Shadowsocks `ivCheck` |

---

## Xray vs V2Ray

Xray is a fork of V2Ray created by the XTLS team in 2020. It's a strict superset — nearly all V2Ray configs run in Xray unchanged.

### Xray-exclusive features

| Feature | Xray | V2Ray | Min Xray version |
|---|---|---|---|
| XTLS Vision flow (`xtls-rprx-vision`) | ✅ | ❌ | ≥ v1.7.2 |
| REALITY (TLS handshake theft) | ✅ | ❌ | ≥ v1.8.0 |
| XHTTP / SplitHTTP transport | ✅ | ❌ | ≥ v24.10.31 (full: v24.11.30) |
| HTTPUpgrade transport | ✅ | ❌ | ≥ v1.8.9 |
| Shadowsocks 2022 | ✅ | ❌ | ≥ v1.7.0 |
| JSONC (comments in config) | ✅ | ❌ | — |
| `rejectUnknownSni` in tlsSettings | ✅ | ❌ | — |
| `ocspStapling` per-certificate | ✅ | ❌ | — |
| `splice` syscall (zero-copy on Linux) | ✅ | ❌ | — |
| `xver` (PROXY protocol in fallbacks) | ✅ | ❌ | — |
| `acceptProxyProtocol` in rawSettings | ✅ | ❌ | — |

### Shared features

- Protocols: VMess, VLESS (basic), Trojan, Shadowsocks (classic), dokodemo-door
- Transports: WebSocket, gRPC, TCP/RAW, HTTP/2 (H2C), mKCP
- Routing, DNS, Policy, Stats — identical architecture

### Compatibility notes

**`raw` vs `tcp`:** Xray renamed `"network": "tcp"` to `"network": "raw"`. lxhao61 configs use `"raw"`. Xray accepts both; V2Ray only accepts `"tcp"`.

**VMess alterId:** V2Ray supports `alterId > 0` (legacy anti-replay). In Xray `alterId` is deprecated — must be `0`. Clients with `alterId > 0` will not connect to an Xray server with `alterId: 0`.

**Performance:** Xray uses Linux `splice()` for zero-copy in Vision/XTLS mode — significantly reduces CPU load at high throughput.

**When V2Ray is still needed:** clients requiring VMess with `alterId > 0`, old panel compatibility, or policy requiring the reference implementation. In all other cases Xray is strictly preferred.

---

## Connection variants: Local Loopback vs Unix Domain Sockets

Every lxhao61 composite config comes in two variants:

| Variant | Connections | Pros | Cons |
|---|---|---|---|
| `1_*` (Local Loopback) | `127.0.0.1:PORT` | Easy to debug; standard tooling | Small TCP stack overhead |
| `2_*` (Unix Domain Sockets) | `/dev/shm/*.sock` | No TCP overhead; faster IPC | Requires permission management |

Caddy UDS uses abstract socket mode (`@socket-name`) — no path or permissions needed. Nginx UDS requires explicit permission configuration.

---

## PROXY protocol — real IP across proxy layers

When Nginx stream or Xray fallbacks sit between the client and the inbound that logs traffic, the real client IP needs to be forwarded explicitly:

| Layer | Mechanism |
|---|---|
| Nginx stream → Xray inbound | `proxy_protocol on` in stream server; `rawSettings.acceptProxyProtocol: true` in Xray |
| Xray fallback → Nginx/Caddy | `xver: 1` or `xver: 2` in fallbacks or realitySettings |
| Nginx receives PROXY protocol | `listen ... proxy_protocol` + `real_ip_header proxy_protocol` |
| Caddy receives PROXY protocol | Native ≥ v2.7.0; otherwise caddy2-proxyprotocol plugin |

---

## Trojan F-pattern: intentional TLS fingerprint differentiation

In the E+F composite (VLESS+Vision+TLS + Trojan+RAW+TLS), F is deliberately configured with a different TLS fingerprint than E:

- **E:** AES-GCM ciphers, TLS 1.2–1.3
- **F:** CHACHA20-POLY1305 only, TLS 1.2 max

```jsonc
"minVersion": "1.2",
"maxVersion": "1.2",
"cipherSuites": "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256:TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
```

Two different TLS fingerprints on two different domains make traffic correlation harder.

---

## Maximum protocol stack on one server

With Xray + Nginx (or Caddy) + Hysteria, one machine can run up to 8 independent protocols:

| # | Protocol | Entry point | Certificate |
|---|---|---|---|
| 1 | VLESS + Vision + REALITY (M) | TCP:443 | ❌ |
| 2 | VLESS + XHTTP + REALITY nested (K) | TCP:443 via M fallback | ❌ |
| 3 | Trojan + RAW + TLS (F) | TCP:443 via SNI routing | ✅ separate domain |
| 4 | VLESS + XHTTP + TLS (H) | TCP:443 → Nginx | ✅ domain (CDN) |
| 5 | NaiveProxy (N) | TCP:443 + UDP:443 | ✅ auto (Caddy) |
| 6 | Trojan-Go (T) | TCP:443 → Caddy | ✅ (shared with N) |
| 7 | VLESS + mKCP (A) | UDP:2052 | ❌ |
| 8 | Hysteria v2 | UDP:443 or UDP:2083 | ✅ auto (ACME) |

**3 processes** (Xray + Nginx or Caddy + Hysteria), **2 external ports** (TCP:443, UDP:443/2052/2083).

### Practical minimum for most scenarios

```
TCP:443 → Nginx stream
    ├── VLESS+Vision+REALITY (M)   — direct clients, maximum concealment
    │       └── fallback → nested XHTTP+REALITY (K)   — free, same inbound as H
    └── VLESS+XHTTP+TLS (H)        — clients via CDN

UDP:443  → Hysteria v2             — unstable links, high packet loss
UDP:2052 → VLESS+mKCP (A)         — alternative UDP

= 4 protocols (5 client configs including K)
= 1 domain + 1 certificate
= 2 processes (Xray + Nginx)
```

This is exactly the M+H+K+A+Nginx pattern from lxhao61, plus Hysteria.

### HTTP/3 vs Hysteria conflict on UDP:443

Both want UDP:443. Three solutions:
1. Move HTTP/3 (Nginx/Caddy) and Hysteria to different UDP ports.
2. Caddy with `udpsni` routing: SNI `h2y.example.com` → Hysteria :3443, others → HTTP/3 server.
3. Hysteria on UDP:2083 with salamander obfs (avoids QUIC blocking, stays on separate port).

---

## Unique patterns

| Pattern | Where | Description |
|---|---|---|
| XTLS Vision | VLESS-TCP-XTLS-Vision, AiO | Eliminates TLS-in-TLS artifact; only with `flow: xtls-rprx-vision` |
| REALITY | VLESS-XHTTP-Reality, VLESS-Vision-Reality | No cert; steals third-party site's TLS handshake |
| Reality target = own Nginx | lxhao61 M+H+K+A | `realitySettings.target = :8443` (own Nginx); active probing gets your cert from your IP |
| Unix Domain Sockets | All-in-One, VLESS-XHTTP3-Nginx | Nginx without a TCP port; less overhead |
| PROXY protocol (xver) | All-in-One fallbacks, lxhao61 all composites | `xver: 2` in fallbacks → real IP in all sub-inbounds |
| dokodemo-door as Reality guard | VLESS-TCP-REALITY (without being stolen) | Prevents Reality inbound from being hijacked by unauthorized clients |
| MITM CA | MITM-Domain-Fronting | Xray as MITM with self-signed CA; requires CA installed in client OS |
| Serverless | Serverless-for-Iran | Cloudflare Workers as transit |
| SS 2022 multi-user | All-in-One, lxhao61 | Master key + per-user sub-keys |
| Nested XHTTP (K) | lxhao61 M+K, M+H+K+A | Client connects via Reality (M), falls back to XHTTP sub-inbound (H); no extra server config |
| F-pattern TLS fingerprint | lxhao61 E+F+H+A | Trojan with non-AES cipher on separate domain; distinct fingerprint from VLESS+Vision |
