# lxhao61 E+F+H+A + Nginx — Production конфиг (SNI routing + TLS)

Источник: [lxhao61/integrated-examples — Xray(E+F+H+A)+Nginx](https://github.com/lxhao61/integrated-examples/tree/main/Xray(E%2BF%2BH%2BA)%2BNginx)

## Что включено

| Буква | Протокол | Транспорт | Домен | Особенность |
|---|---|---|---|---|
| E | VLESS + Vision | TLS (Xray терминирует) | h2t.example.com | Fallback → Nginx :88 |
| F | Trojan + RAW | TLS 1.2 + CHACHA20 | t2n.example.com | Non-AES, другой fingerprint |
| H | VLESS + XHTTP | TLS (Nginx терминирует) | cdn / h3a | CDN-совместимый |
| A | VLESS + mKCP | seed | — | UDP :2052 |

## Файлы

- `xray.jsonc` — конфиг Xray (Local Loopback + PROXY protocol, вариант 1)
- `nginx.conf` — Nginx stream (SNI routing) + HTTP/2/3 server blocks
- `README-upstream.md` — оригинальный README от lxhao61 (на китайском)

## Требования

- Xray **≥ v24.11.30**
- Nginx **≥ v1.25.1** (для H2C + HTTP/1.1 на одном порту через `listen :88`)
- 4 домена с A-записями: `h2t`, `t2n`, `cdn`, `h3a` → все на один IP
- TLS-сертификаты для каждого домена (или один wildcard/SAN)
- Nginx собран с `--with-stream --with-stream_ssl_preread_module --with-http_realip_module`

## Архитектура

```
Internet :443 (TCP)
    │
    ▼
Nginx stream (SNI routing + proxy_protocol ON глобально)
    ├── h2t.example.com  →  :5443  Xray VLESS+Vision+TLS (E)
    │                              └── fallback :88 → Nginx HTTP (decoy)
    ├── t2n.example.com  →  :6443  Xray Trojan+RAW+TLS (F)
    │                              └── fallback :88 → Nginx HTTP (decoy)
    ├── cdn.example.com  →  :7443  Nginx HTTPS/H2 (CDN proxy for H)
    │                              └── grpc_pass :2023 (VLESS+XHTTP)
    └── h3a.example.com  →  :8443  Nginx HTTPS/H2+H3
                                   └── grpc_pass :2023 (VLESS+XHTTP)

Nginx QUIC :443 UDP  — HTTP/3 (не конфликтует с stream TCP:443)
VLESS+mKCP :2052 UDP — mKCP (A)
```

## Что заменить в xray.jsonc

| Placeholder | Что поставить | Команда |
|---|---|---|
| `048e0bf2-dd56-...` | UUID клиента E | `xray uuid` |
| `diy6443` | Trojan password (F) | любая строка |
| `af7d5cf8-442d-...` | UUID клиента H | `xray uuid` |
| `0a652466-dd56-...` | UUID клиента A | `xray uuid` |
| `/home/tls/h2t.example.com/...` | Путь к сертификату E | после acme.sh |
| `/home/tls/t2n.example.com/...` | Путь к сертификату F | после acme.sh |
| `/VLSpdG9k` | Случайный path для XHTTP | `openssl rand -hex 8` |
| `60VoqhfjP79nBQyU` | mKCP seed | любая случайная строка |

## Важно: PROXY protocol

Nginx stream включает `proxy_protocol on` **глобально** для всех upstream. Это значит:

1. Xray inbound E и F должны иметь `"acceptProxyProtocol": true` в `rawSettings`
2. Nginx HTTP server (port 88) должен принимать `proxy_protocol` в `listen`
3. Nginx HTTPS servers (7443, 8443) — аналогично

Цепочка передачи реального IP:
```
Client → Nginx stream (proxy_protocol send) → Xray E/F (acceptProxyProtocol)
                                             → Nginx HTTP :88 (real_ip_header proxy_protocol)
```

## TLS для Trojan (буква F) — намеренно non-AES

Trojan использует `TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256` и `maxVersion: 1.2`.
Это делает fingerprint трафика F визуально отличным от E (AES-GCM, TLS 1.3).
Два протокола на разных доменах с разными TLS-характеристиками усложняют детектирование.

> Оригинальные Trojan и Trojan-Go **клиенты** не поддерживают TLS fingerprint spoofing — использовать только Xray-клиент с Trojan-протоколом.

## Subscription Links

**E (VLESS+Vision+TLS):**
```
vless://UUID_E@h2t.example.com:443?security=tls&encryption=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=h2t.example.com#E
```

**F (Trojan+TLS):**
```
trojan://diy6443@t2n.example.com:443?security=tls&type=tcp&sni=t2n.example.com#F
```

**H (VLESS+XHTTP+TLS через CDN):**
```
vless://UUID_H@cdn.example.com:443?security=tls&encryption=none&type=xhttp&path=/VLSpdG9k&sni=cdn.example.com#H
```
