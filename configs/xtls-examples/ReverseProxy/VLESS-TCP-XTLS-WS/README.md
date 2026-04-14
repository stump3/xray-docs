# VLESS over TCP+XTLS with WebSocket fallback — ReverseProxy

Uses port 443 with XTLS + WS fallback and routing rules to implement a reverse proxy with improved concealment.

Two client connection modes:
- **VLESS over TCP + XTLS** — direct, high performance
- **VLESS over WebSocket + TLS** — CDN-compatible

## How it works

```
Client (XTLS or WS) → Portal :443 → Bridge (internal server)
                            │
                            └── fallback :80 → Web server (decoy)
```

Portal defaults fallback to a web server on port 80 (can be replaced with any local service).

## Routing split (optional)

If the portal is outside your country, you can enable split routing to simultaneously browse the internet and access internal network resources. In `portal.jsonc`, uncomment the routing rule that forwards traffic tagged `"external"` or `"externalws"` with a private IP destination to the bridge — everything else goes direct.
