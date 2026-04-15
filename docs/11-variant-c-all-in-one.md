# 11 — Variant C: All-in-One, 17 протоколов

Разбор оригинального конфига `XTLS/Xray-examples — All-in-One-fallbacks-Nginx` с пошаговым объяснением routing-логики и шаблоном для лабораторного стенда.

Источник конфига: [`configs/xtls-examples/All-in-One-fallbacks/`](../configs/xtls-examples/All-in-One-fallbacks/)

---

## Полный список протоколов

| # | Протокол | Транспорт | Routing-ключ | Socket / Port |
|---|---|---|---|---|
| 1 | **VLESS + Vision + TLS** | TCP | — (основной entrypoint) | `:443` |
| 2 | VLESS + TCP + TLS | TCP + http obfuscation | `path=/vltc` | `@vless-tcp` (UDS) |
| 3 | VLESS + WebSocket + TLS | WebSocket | `path=/vlws` | `@vless-ws` (UDS) |
| 4 | VLESS + gRPC + TLS | gRPC | `alpn=h2` → Nginx `/vlgrpc` | `127.0.0.1:3002` |
| 5 | VLESS + H2 + TLS | HTTP/2 | `alpn=h2` + `SNI=vlh2o.*` | `@vless-h2` (UDS) |
| 6 | VMess + TCP + TLS | TCP + http obfuscation | `path=/vmtc` | `@vmess-tcp` (UDS) |
| 7 | VMess + WebSocket + TLS | WebSocket | `path=/vmws` | `@vmess-ws` (UDS) |
| 8 | VMess + gRPC + TLS | gRPC | `alpn=h2` → Nginx `/vmgrpc` | `127.0.0.1:3003` |
| 9 | VMess + H2 + TLS | HTTP/2 | `alpn=h2` + `SNI=vmh2o.*` | `@vmess-h2` (UDS) |
| 10 | Trojan + TCP + TLS | TCP | `alpn=h2` (generic) | `@trojan-tcp` (UDS) |
| 11 | Trojan + WebSocket + TLS | WebSocket | `path=/trojanws` | `@trojan-ws` (UDS) |
| 12 | Trojan + gRPC + TLS | gRPC | `alpn=h2` → Nginx `/trgrpc` | `127.0.0.1:3001` |
| 13 | Trojan + H2 + TLS | HTTP/2 | `alpn=h2` + `SNI=trh2o.*` | `@trojan-h2` (UDS) |
| 14 | Shadowsocks + TCP + TLS | TCP + http obfuscation | `path=/sstc` | `127.0.0.1:4002` |
| 15 | Shadowsocks + WebSocket + TLS | WebSocket | `path=/ssws` | `127.0.0.1:4001` |
| 16 | Shadowsocks + gRPC | gRPC | `alpn=h2` → Nginx `/ssgrpc` | `127.0.0.1:3004` |
| 17 | Shadowsocks + H2 + TLS | HTTP/2 | `alpn=h2` + `SNI=ssh2o.*` | `127.0.0.1:4003` |

Все 17 доступны на одном внешнем порту **TCP:443**.

---

## Как работает routing

Точка входа — единственный inbound `VLESS+TCP+TLS+Vision` на `:443`. После TLS-терминации Xray смотрит на три параметра запроса и маршрутизирует через `fallbacks`:

```
Входящий запрос на :443
    │
    ├── 1. SNI + ALPN = h2  →  SNI-specific H2 sub-inbounds (#5, #9, #13, #17)
    │
    ├── 2. path = /vlws     →  VLESS WebSocket     (#3)
    ├── 2. path = /vmws     →  VMess WebSocket      (#7)
    ├── 2. path = /trojanws →  Trojan WebSocket     (#11)
    ├── 2. path = /ssws     →  Shadowsocks WS       (#15)
    ├── 2. path = /vltc     →  VLESS TCP obfs       (#2)
    ├── 2. path = /vmtc     →  VMess TCP obfs       (#6)
    ├── 2. path = /sstc     →  Shadowsocks TCP obfs (#14)
    │
    ├── 3. alpn = h2        →  @trojan-tcp          (#10)
    │       └── trojan-tcp fallback:
    │               ├── valid Trojan password  →  proxied
    │               └── invalid (probing/gRPC) →  h2c.sock → Nginx
    │                       └── Nginx h2c.sock:
    │                               ├── /trgrpc   →  Trojan gRPC   (#12)
    │                               ├── /vlgrpc   →  VLESS gRPC    (#4)
    │                               ├── /vmgrpc   →  VMess gRPC    (#8)
    │                               ├── /ssgrpc   →  SS gRPC       (#16)
    │                               └── /         →  decoy сайт
    │
    └── 4. default          →  h1.sock → Nginx HTTP/1.1 → decoy сайт
```

### Почему gRPC проходит через двойной fallback

gRPC использует HTTP/2, поэтому ALPN=h2. Xray не умеет отличать gRPC от обычного H2 по `alpn` — оба попадают в `@trojan-tcp`. Там Trojan пытается проверить пароль. Если запрос не выглядит как Trojan (gRPC-запрос им не является) — второй fallback в `h2c.sock`. Nginx уже видит путь gRPC-запроса (`/trgrpc`, `/vlgrpc` и т.д.) и направляет в нужный Xray inbound.

```
gRPC клиент → :443 (alpn=h2) → @trojan-tcp → h2c.sock → Nginx → grpc_pass :3001-3004
```

### Почему H2 идёт по SNI, а не по path

H2 не поддерживает fallback по `path` — это ограничение транспорта HTTP/2. Вместо этого каждый H2-протокол получает отдельный субдомен, и Xray смотрит на SNI в ClientHello:

```
SNI=trh2o.example.com + alpn=h2  →  @trojan-h2
SNI=vlh2o.example.com + alpn=h2  →  @vless-h2
SNI=vmh2o.example.com + alpn=h2  →  @vmess-h2
SNI=ssh2o.example.com + alpn=h2  →  127.0.0.1:4003
```

Wildcard-сертификат (`*.example.com`) покрывает все субдомены одним cert.

---

## Сокеты и порты

```
:443 TCP              ← внешний, Xray
@vless-ws             ← Unix Domain Socket (abstract)
@vmess-ws             ← Unix Domain Socket (abstract)
@trojan-ws            ← Unix Domain Socket (abstract)
@trojan-tcp           ← Unix Domain Socket (abstract)
@vless-tcp            ← Unix Domain Socket (abstract)
@vmess-tcp            ← Unix Domain Socket (abstract)
@trojan-h2            ← Unix Domain Socket (abstract)
@vless-h2             ← Unix Domain Socket (abstract)
@vmess-h2             ← Unix Domain Socket (abstract)
127.0.0.1:3001        ← Trojan gRPC
127.0.0.1:3002        ← VLESS gRPC
127.0.0.1:3003        ← VMess gRPC
127.0.0.1:3004        ← Shadowsocks gRPC
127.0.0.1:4001        ← Shadowsocks WebSocket
127.0.0.1:4002        ← Shadowsocks TCP
127.0.0.1:4003        ← Shadowsocks H2
/dev/shm/h1.sock      ← Nginx HTTP/1.1 UDS (decoy)
/dev/shm/h2c.sock     ← Nginx H2C UDS (gRPC routing)
62789                 ← dokodemo-door API
```

Xray sub-inbounds используют **abstract Unix sockets** (с `@`-префиксом) — они существуют только в памяти ядра, без файла на диске, без прав доступа. Nginx использует **path-based sockets** (`/dev/shm/*.sock`) — их нужно создать перед запуском Xray, иначе Xray упадёт при старте.

---

## Предварительные требования

### TLS-сертификаты

| Что нужно | Для чего |
|---|---|
| Сертификат `example.com` | Основной домен (decoy сайт, WS, TCP) |
| Wildcard `*.example.com` или SAN | H2 субдомены (trh2o, vlh2o, vmh2o, ssh2o) |
| Сертификат `behindcdn.com` (опционально) | CDN-домен (закомментирован в основном конфиге) |

Проще всего — один wildcard cert на `*.example.com + example.com`.

### Nginx с нужными модулями

```bash
nginx -V 2>&1 | grep -E 'stream|http_v2|http_realip|http_ssl'
```

Нужны: `http_ssl_module`, `http_v2_module`, `http_realip_module`.  
gRPC требует Nginx ≥ v1.13.10 для `grpc_pass`.

### Порядок запуска

```bash
# 1. Запустить Nginx — он создаёт /dev/shm/*.sock
systemctl start nginx

# 2. Убедиться что сокеты созданы
ls /dev/shm/h1.sock /dev/shm/h2c.sock

# 3. Только потом запускать Xray
systemctl start xray
```

Если запустить Xray первым — он попытается писать в несуществующие сокеты и упадёт.

---

## Переменные для шаблона (лабораторный стенд)

```bash
# --- Домен и IP ---
DOMAIN=example.com           # основной домен
CDN_DOMAIN=behindcdn.com     # CDN домен (опционально)
SERVER_IP=1.2.3.4

# --- TLS сертификаты ---
CERT_FILE=/etc/ssl/example.com/domain.pem
KEY_FILE=/etc/ssl/example.com/domain-key.pem
CDN_CERT_FILE=/etc/ssl/behindcdn.com/domain.pem
CDN_KEY_FILE=/etc/ssl/behindcdn.com/domain-key.pem

# --- UUID (один для всех VLESS + VMess) ---
UUID=90e4903e-66a4-45f7-abda-fd5d5ed7f797

# --- Trojan / Shadowsocks пароль ---
TR_PASSWORD=your-trojan-password
SS_PASSWORD=your-ss-password
SS_METHOD=chacha20-ietf-poly1305

# --- Пути WebSocket + TCP obfs ---
VLESS_WS_PATH=/vlws
VMESS_WS_PATH=/vmws
TROJAN_WS_PATH=/trojanws
SS_WS_PATH=/ssws
VLESS_TC_PATH=/vltc
VMESS_TC_PATH=/vmtc
SS_TC_PATH=/sstc

# --- gRPC service names ---
TROJAN_GRPC_SVC=trgrpc
VLESS_GRPC_SVC=vlgrpc
VMESS_GRPC_SVC=vmgrpc
SS_GRPC_SVC=ssgrpc

# --- H2 субдомены ---
TROJAN_H2_SNI=trh2o.${DOMAIN}
VLESS_H2_SNI=vlh2o.${DOMAIN}
VMESS_H2_SNI=vmh2o.${DOMAIN}
SS_H2_SNI=ssh2o.${DOMAIN}

# --- Внутренние порты (gRPC и SS sub-inbounds) ---
TROJAN_GRPC_PORT=3001
VLESS_GRPC_PORT=3002
VMESS_GRPC_PORT=3003
SS_GRPC_PORT=3004
SS_WS_PORT=4001
SS_TC_PORT=4002
SS_H2_PORT=4003

# --- Unix sockets ---
H1_SOCK=/dev/shm/h1.sock
H2C_SOCK=/dev/shm/h2c.sock

# --- API ---
API_PORT=62789

# --- Клиент ---
SOCKS_PORT=1080
HTTP_PORT=8118
```

---

## Subscription links

### VLESS (Vision + TLS, основной)
```
vless://UUID@DOMAIN:443?security=tls&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=DOMAIN&fp=chrome#C-VLESS-Vision
```

### VLESS + WebSocket
```
vless://UUID@DOMAIN:443?security=tls&encryption=none&type=ws&path=VLESS_WS_PATH&sni=DOMAIN&fp=chrome#C-VLESS-WS
```

### VLESS + gRPC
```
vless://UUID@DOMAIN:443?security=tls&encryption=none&type=grpc&serviceName=VLESS_GRPC_SVC&sni=DOMAIN&fp=chrome#C-VLESS-gRPC
```

### VLESS + H2
```
vless://UUID@VLESS_H2_SNI:443?security=tls&encryption=none&type=http&path=/vlh2&sni=VLESS_H2_SNI&fp=chrome#C-VLESS-H2
```

### VMess + WebSocket
```
vmess://BASE64({v:2,ps:"C-VMess-WS",add:DOMAIN,port:443,id:UUID,net:ws,path:VMESS_WS_PATH,tls:tls,sni:DOMAIN,fp:chrome})
```

### Trojan + TCP
```
trojan://TR_PASSWORD@DOMAIN:443?security=tls&type=tcp&sni=DOMAIN&fp=chrome#C-Trojan-TCP
```

### Trojan + WebSocket
```
trojan://TR_PASSWORD@DOMAIN:443?security=tls&type=ws&path=TROJAN_WS_PATH&sni=DOMAIN&fp=chrome#C-Trojan-WS
```

### Trojan + gRPC
```
trojan://TR_PASSWORD@DOMAIN:443?security=tls&type=grpc&serviceName=TROJAN_GRPC_SVC&sni=DOMAIN&fp=chrome#C-Trojan-gRPC
```

### Shadowsocks + WebSocket
```
# SS не имеет стандартного URI с WS. Использовать v2ray-plugin или клиент с поддержкой WS-транспорта.
ss://BASE64(SS_METHOD:SS_PASSWORD)@DOMAIN:SS_WS_PORT?plugin=v2ray-plugin;mode=websocket;path=SS_WS_PATH#C-SS-WS
```

---

## Переход от текущего Variant C (2 протокола) к полным 17

Текущий лабораторный Variant C имеет: VLESS+WS + VMess+WS + Nginx decoy через h1.sock.  
Путь расширения — по группам, каждая тестируется отдельно:

### Шаг 1 — Добавить Vision flow к главному inbound (уже описан в 09)

Единственное изменение — поле в конфиге клиента. Архитектурно ничего не меняется.

### Шаг 2 — ALPN prerequisite: добавить `"h2"` в список

```jsonc
"tlsSettings": {
  "alpn": ["h2", "http/1.1"],   // ← было только ["http/1.1"]
  ...
}
```

Без `"h2"` в ALPN gRPC и H2 клиенты не согласуют протокол.

### Шаг 3 — Добавить Trojan+TCP через `alpn=h2` fallback + h2c.sock

Это открывает путь для gRPC. Пока Nginx h2c.sock отдаёт только decoy — gRPC inbound-ы добавляются потом.

```jsonc
// В fallbacks главного inbound — добавить перед default:
{ "alpn": "h2", "dest": "${H2C_SOCK}", "xver": 2 }
```

```bash
# Nginx: добавить h2c.sock server block (см. оригинальный nginx.conf)
```

### Шаг 4 — gRPC: по одному inbound за раз

Добавлять gRPC inbound-ы по одному: Trojan gRPC → VLESS gRPC → VMess gRPC → SS gRPC.  
После каждого — проверить `make test-proxy` с gRPC-клиентом.

```jsonc
{
  "tag": "trojan-grpc",
  "listen": "127.0.0.1",
  "port": ${TROJAN_GRPC_PORT},
  "protocol": "trojan",
  "settings": { "clients": [{ "password": "${TR_PASSWORD}" }] },
  "streamSettings": {
    "network": "grpc",
    "security": "none",
    "grpcSettings": { "serviceName": "${TROJAN_GRPC_SVC}" }
  }
}
```

Nginx location (в h2c.sock server block):
```nginx
location /${TROJAN_GRPC_SVC} {
    if ($request_method != "POST") { return 404; }
    grpc_pass grpc://127.0.0.1:${TROJAN_GRPC_PORT};
}
```

### Шаг 5 — Добавить Trojan+WebSocket и Trojan+TCP obfs

```jsonc
// В fallbacks — добавить Trojan WS:
{ "path": "${TROJAN_WS_PATH}", "dest": "@trojan-ws", "xver": 2 }

// Новый sub-inbound:
{
  "listen": "@trojan-ws",
  "protocol": "trojan",
  "settings": { "clients": [{ "password": "${TR_PASSWORD}" }] },
  "streamSettings": {
    "network": "ws",
    "wsSettings": { "acceptProxyProtocol": true, "path": "${TROJAN_WS_PATH}" }
  }
}
```

### Шаг 6 — H2 sub-inbounds

H2 требует субдоменов с DNS A-записями, указывающими на сервер. Добавлять по одному:

```jsonc
// В fallbacks — добавить перед generic alpn=h2:
{ "name": "${TROJAN_H2_SNI}", "alpn": "h2", "dest": "@trojan-h2" }

// Новый sub-inbound:
{
  "listen": "@trojan-h2",
  "protocol": "trojan",
  "settings": { "clients": [{ "password": "${TR_PASSWORD}" }] },
  "streamSettings": {
    "network": "h2",
    "httpSettings": { "path": "/trh2" }
  }
}
```

> **Важно:** H2 fallbacks должны идти **раньше** generic `alpn=h2` fallback в массиве. Xray проверяет fallbacks по порядку — если generic `alpn=h2` стоит первым, он перехватит всё и H2 sub-inbounds никогда не сработают.

### Шаг 7 — Shadowsocks sub-inbounds

Shadowsocks sub-inbounds слушают на TCP-портах (не UDS), потому что `@`-сокеты не поддерживают PROXY protocol v2 для SS без дополнительной настройки. Добавить в порядке: WS → TCP → gRPC → H2.

---

## Отличия от лабораторного шаблона (текущий Variant C)

| Аспект | Текущий Variant C | Full All-in-One |
|---|---|---|
| Протоколов | 2 (VLESS+WS, VMess+WS) | 17 |
| Nginx decoy | TCP-порт `127.0.0.1:DECOY_PORT` | Unix sockets (`h1.sock`, `h2c.sock`) |
| UDS sub-inbounds | ❌ | ✅ abstract `@tag` sockets |
| PROXY protocol | `xver:1` | `xver:2` (версия 2 — более эффективная) |
| Vision flow | ❌ (в текущем шаблоне) | ✅ на главном inbound |
| ALPN | `["http/1.1"]` | `["h2", "http/1.1"]` |
| Shadowsocks | ❌ | ✅ 4 транспорта |
| Trojan | ❌ | ✅ 4 транспорта |
| gRPC | ❌ | ✅ 4 inbound через Nginx h2c |
| H2 | ❌ | ✅ 4 inbound через SNI |
| Статистика | ✅ StatsService | ✅ Stats + HandlerService + LoggerService |

---

## Что стоит изменить перед production-использованием

Оригинальный конфиг от XTLS написан для v1.7.2 и содержит несколько устаревших деталей:

| Проблема | В оригинале | Актуально |
|---|---|---|
| Логирование | `loglevel: "info"` | `loglevel: "warning"` |
| TLS flow | `xtls-rprx-vision` (закомментирован `xtls-rprx-direct`) | только `xtls-rprx-vision` |
| SS method | `chacha20-ietf-poly1305` (AEAD) | `2022-blake3-aes-128-gcm` (SS 2022) |
| PROXY protocol | `xver: 2` ✅ | `xver: 2` — актуально |
| SS sub-inbounds | TCP-порты | TCP-порты — приемлемо, UDS без выигрыша |
| Один UUID для всех | ✅ удобно для теста | В production — отдельный UUID per protocol/user |
