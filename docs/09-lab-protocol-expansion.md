# 09 — Расширение протоколов: Variant A и Variant B

Документ описывает пошаговое добавление протоколов к базовым конфигурациям лабораторного стенда. Каждый шаг изолирован — сначала добавляется один протокол, прогоняются тесты, только потом следующий.

---

## О полях `dest` и `target` в `realitySettings`

В Xray v24.10.31 поле `dest` в `realitySettings` было переименовано в `target`. Старое имя оставлено как **алиас** — конфиги с `dest` продолжают работать на всех версиях, Xray принимает оба варианта.

Тем не менее **используй `target`** — это актуальное имя в официальной документации и в конфигах большинства людей. При чтении чужих конфигов встречается именно `target`, и несоответствие создаёт путаницу.

```jsonc
// Устарело (но работает как алиас):
"realitySettings": {
  "dest": "www.microsoft.com:443"
}

// Актуально:
"realitySettings": {
  "target": "www.microsoft.com:443"
}
```

В шаблоне `scenarios/variant-b/xray-server.json.tpl` исправлено на `target`.

---

## Variant A — VLESS + XHTTP + Reality

### Текущее состояние

```
Internet :443 (TCP)
    │
    ▼
Xray — VLESS + XHTTP + Reality
    │
    └── Nginx :8080  (subscription endpoint, опционально)
```

Один inbound, один протокол. Nginx не участвует в проксировании.

### Потолок архитектуры A

Xray занимает :443 целиком — нет промежуточного роутера. Reality несовместима с `fallbacks` (они работают на разных уровнях стека). Это означает:

- добавить второй протокол на :443 напрямую нельзя
- CDN-совместимые протоколы (WS, XHTTP+TLS) требуют Nginx перед Xray
- единственное расширение без смены архитектуры — **mKCP на отдельном UDP-порту**

---

### A.1 — mKCP на UDP:2052

mKCP работает поверх UDP и не конфликтует с TCP:443. Это полностью независимый inbound — добавляется без каких-либо изменений в существующий Reality inbound.

**Когда использовать:** там где UDP не заблокирован и нужна высокая пропускная способность при потерях пакетов.

**Ограничения:** не работает через CDN; seed — единственная защита от несанкционированного использования (не криптографическая), поэтому рекомендуется использовать длинный случайный seed.

#### Изменения в `vars.env`

```bash
# --- mKCP (UDP, отдельный порт) ---
MKCP_PORT=2052
MKCP_SEED=your-random-seed-here   # make keys сгенерирует автоматически
```

Генерация seed:
```bash
openssl rand -base64 18 | tr -d '=+/'   # ~24 случайных символа
```

#### Изменения в `xray-server.json.tpl`

Добавить новый inbound в массив `inbounds[]`:

```jsonc
{
  "tag": "mkcp-in",
  "port": ${MKCP_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id":    "${UUID}",      // тот же UUID что у XHTTP, или отдельный
        "email": "user-mkcp",
        "level": 0
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "kcp",
    "kcpSettings": {
      "uplinkCapacity":   100,
      "downlinkCapacity": 100,
      "congestion":       true,
      "readBufferSize":   5,
      "writeBufferSize":  5,
      "seed":             "${MKCP_SEED}"
    }
  },
  "sniffing": {
    "enabled":      true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly":    true
  }
}
```

#### Subscription link

```
vless://UUID@SERVER_IP:MKCP_PORT?security=none&encryption=none&type=kcp&seed=MKCP_SEED#A-mKCP
```

#### Тест

```bash
# Открыть порт в firewall
ufw allow ${MKCP_PORT}/udp

# Проверить что UDP-порт слушается
ss -ulnp | grep :${MKCP_PORT}

# Прогнать тест через SOCKS5 (после запуска клиентского xray с mKCP-конфигом)
make test-proxy VAR=variant-a
```

#### Переход дальше

После успешного теста mKCP — это предел Варианта A. Для добавления CDN-протоколов нужно перейти на **Variant B** (Nginx stream перед Xray).

---

## Variant B — Nginx stream SNI routing

### Текущее состояние

```
Internet :443 (TCP)
    │
    ▼
Nginx stream (SNI routing)
    ├── SNI = DOMAIN       → Nginx HTTPS :NGINX_HTTPS_PORT
    │                           ├── /         → decoy сайт
    │                           ├── /sub      → subscription
    │                           └── /WS_PATH  → Xray WS inbound :WS_INBOUND_PORT
    └── SNI = всё остальное → Xray Reality :REALITY_INBOUND_PORT
                                  └── VLESS + Vision + Reality
```

Два протокола: Reality (прямые клиенты) и VLESS+WS+TLS (CDN-клиенты).

---

### B.1 — XHTTP+TLS вместо WS (или рядом)

XHTTP — более современный транспорт чем WebSocket: разделяет upload/download на отдельные HTTP-запросы, что существенно затрудняет анализ трафика по временны́м паттернам одного соединения. При этом XHTTP так же CDN-совместим как WS.

**Рекомендация:** добавить XHTTP как второй CDN-протокол рядом с WS, а не вместо него — так остаётся fallback на случай если CDN не поддерживает XHTTP-режим (некоторые провайдеры блокируют нестандартные HTTP-запросы).

> **Требования:** Xray ≥ v24.11.30 для полного разделения up/down потоков.

#### Новые переменные в `vars.env`

```bash
# --- XHTTP+TLS inbound (CDN-совместимый) ---
XHTTP_INBOUND_PORT=9003      # только 127.0.0.1, произвольный
XHTTP_PATH=/your-xhttp-path  # случайный, отличный от WS_PATH
UUID_XHTTP=zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz   # make keys
```

#### Новый inbound в `xray-server.json.tpl`

```jsonc
{
  "tag": "xhttp-in",
  "listen": "127.0.0.1",
  "port": ${XHTTP_INBOUND_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id":    "${UUID_XHTTP}",
        "email": "user-xhttp",
        "level": 0
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "path": "${XHTTP_PATH}",
      "mode": "auto"
    }
  },
  "sniffing": {
    "enabled":      true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly":    true
  }
}
```

#### Новый `location` в `nginx.conf.tpl` (в HTTPS server block)

```nginx
location ${XHTTP_PATH} {
    grpc_pass grpc://127.0.0.1:${XHTTP_INBOUND_PORT};
    grpc_set_header Host $host;
    grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    # XHTTP генерирует много запросов с query-строками для padding —
    # access_log лучше отключить после отладки:
    # access_log off;
}
```

#### Subscription link

```
vless://UUID_XHTTP@DOMAIN:443?security=tls&encryption=none&type=xhttp&path=XHTTP_PATH&sni=DOMAIN&fp=chrome#B-XHTTP-TLS
```

#### Тест

```bash
# Проверить что Nginx проксирует XHTTP path
curl -I --http2 -k https://DOMAIN/XHTTP_PATH   # должен вернуть не 404

# Прогнать proxy test с XHTTP-клиентом
make test-proxy VAR=variant-b
```

---

### B.2 — mKCP на UDP:2052

Идентично A.1 — добавить независимый mKCP inbound. Не требует изменений в Nginx.

Добавить в `vars.env`:
```bash
MKCP_PORT=2052
MKCP_SEED=your-random-seed-here
```

Добавить inbound в `xray-server.json.tpl` — точно такой же блок как в A.1 (UUID можно взять тот же что у Reality или отдельный).

Открыть порт:
```bash
ufw allow ${MKCP_PORT}/udp
```

---

### B.3 — XHTTP + Reality (nested, letter K)

**Nested transport** — the client connects via Reality (like M) but uses XHTTP internally. На сервере это реализуется через `fallbacks` в Reality inbound: нераспознанный трафик падает в отдельный XHTTP sub-inbound.

**Главная особенность:** K-клиенты и H-клиенты **шарят один и тот же XHTTP inbound** (`:XHTTP_INBOUND_PORT`). Разница только в точке входа снаружи: H идёт через Nginx TLS, K идёт через Reality.

> **Требование:** Xray ≥ v24.10.31 для поддержки XHTTP + Reality.

#### Изменение Reality inbound в `xray-server.json.tpl`

В существующий `reality-in` inbound добавить `fallbacks`:

```jsonc
{
  "tag": "reality-in",
  "listen": "127.0.0.1",
  "port": ${REALITY_INBOUND_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id":    "${UUID_REALITY}",
        "email": "user-reality",
        "level": 0,
        "flow":  "xtls-rprx-vision"
      }
    ],
    "decryption": "none",
    "fallbacks": [                              // ← добавить этот блок
      {
        "dest": ${XHTTP_INBOUND_PORT}           // тот же inbound что у H
      }
    ]
  },
  "streamSettings": { ... }   // без изменений
}
```

Новых inbound-ов не нужно — K использует уже существующий XHTTP inbound из шага B.1.

#### Subscription link для K

```
vless://UUID_XHTTP@SERVER_IP:443?security=reality&encryption=none&pbk=PUB_KEY&fp=chrome&type=xhttp&path=XHTTP_PATH&sni=REALITY_DOMAIN&sid=SHORT_ID#B-XHTTP-Reality-K
```

Обрати внимание: UUID тот же что у H (`UUID_XHTTP`), потому что оба идут в один inbound.

#### Test: nested Reality

```bash
# K-клиент: подключается через Reality (SERVER_IP:443), но использует XHTTP
# Запустить клиентский xray с K-конфигом, затем:
curl --proxy socks5h://127.0.0.1:${SOCKS_PORT} https://icanhazip.com

# Должен вернуть SERVER_IP — значит Reality-соединение установлено,
# трафик идёт через XHTTP inbound внутри сервера
```

---

### B.4 — HTTP/3 (QUIC) на UDP:443

HTTP/3 работает поверх UDP и **не конфликтует** с Xray, который занимает TCP:443. Nginx добавляет `listen 443 quic` независимо.

> **Требования:** Nginx ≥ v1.25.0 + OpenSSL/BoringSSL с поддержкой QUIC. Проверить:
> ```bash
> nginx -V 2>&1 | grep http_v3_module
> ```

#### Новые переменные в `vars.env`

Дополнительных переменных не нужно — HTTP/3 использует уже существующие `DOMAIN`, `CERT_FILE`, `KEY_FILE`.

#### Изменение в `nginx.conf.tpl`

В основной HTTPS server block добавить:

```nginx
server {
    # Существующие listeners:
    listen ${NGINX_HTTPS_PORT} ssl proxy_protocol;
    http2 on;

    # Добавить QUIC listener (443 UDP, не мешает Xray на TCP:443):
    listen 443 quic reuseport;
    listen [::]:443 quic reuseport;   # если есть IPv6

    server_name ${DOMAIN};

    # Анонс HTTP/3 в заголовке ответа:
    add_header Alt-Svc 'h3=":443"; ma=86400' always;

    # ... остальная конфигурация без изменений
}
```

#### Открыть порт

```bash
ufw allow 443/udp
```

#### Тест

```bash
# Проверить что Nginx отвечает на QUIC
curl --http3 https://${DOMAIN} -I -o /dev/null -w "%{http_version}\n"
# Должно вернуть: 3
```

---

## Итоговая картина после всех расширений

### Variant A (финальный)

```
Internet :443 (TCP) → Xray — VLESS + XHTTP + Reality
Internet :2052 (UDP) → Xray — VLESS + mKCP + seed
Internet :8080 (TCP) → Nginx — subscription endpoint
```

Два независимых протокола, нет роутера.

### Variant B (финальный)

```
Internet :443 (TCP)
    │
    ├── Nginx stream (SNI routing)
    │       ├── SNI = DOMAIN      → Nginx HTTPS :NGINX_HTTPS_PORT
    │       │                          ├── /WS_PATH   → Xray WS :WS_INBOUND_PORT
    │       │                          └── /XHTTP_PATH → Xray XHTTP :XHTTP_INBOUND_PORT
    │       └── SNI = остальное   → Xray Reality :REALITY_INBOUND_PORT
    │                                   └── fallback → Xray XHTTP :XHTTP_INBOUND_PORT (K/nested)
    │
    └── Nginx QUIC UDP:443 → HTTP/3 (независимо от stream TCP)

Internet :2052 (UDP) → Xray — mKCP + seed
```

Пять протоколов, два из которых (H и K) шарят один XHTTP inbound:

| Тег | Протокол | Транспорт | Путь входа |
|---|---|---|---|
| B-Reality | VLESS + Vision | Reality TCP | IP:443 (без SNI домена) |
| B-WS | VLESS | WebSocket + TLS | DOMAIN:443/WS_PATH |
| B-XHTTP (H) | VLESS | XHTTP + TLS | DOMAIN:443/XHTTP_PATH |
| B-XHTTP-R (K) | VLESS | XHTTP + Reality | IP:443 → fallback → XHTTP inbound |
| B-mKCP | VLESS | mKCP seed | IP:2052 UDP |

---

---

## Variant C — Xray native fallbacks

### Текущее состояние

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+TLS (TLS termination, main inbound)
    ├── path=/VLESS_WS_PATH  →  VLESS+WS inbound :9001  (acceptProxyProtocol)
    ├── path=/VMESS_WS_PATH  →  VMess+WS  inbound :9002  (acceptProxyProtocol)
    └── default              →  unix:H1_SOCK → Nginx decoy + /sub
```

Два WebSocket протокола через path-based fallbacks. Nginx слушает только на Unix socket — без TCP-порта.

### Особенности архитектуры C

**Reality недоступна** — Reality работает до TLS handshake, fallbacks работают после расшифровки. Эти механизмы взаимоисключающие на одном inbound.

**Порядок запуска важен** — Nginx должен создать Unix socket до того как Xray начнёт в него писать. `run.sh up` запускает Nginx первым и ждёт появления сокета.

**Vision flow уже можно добавить** — в существующих клиентах главного inbound это просто поле в конфиге, без архитектурных изменений.

---

### C.0 — Vision flow (prereq, не новый протокол)

Добавить `"flow": "xtls-rprx-vision"` в клиент главного inbound. Это улучшает скрытность соединения за счёт обработки TLS-in-TLS паттернов. Не требует новых inbound-ов.

В `xray-server.json.tpl` в блоке `vless-tls-main`:

```jsonc
"clients": [
  {
    "id":    "${UUID_VLESS}",
    "email": "user-vless",
    "level": 0,
    "flow":  "xtls-rprx-vision"   // ← добавить
  }
],
```

В `vars.env` изменений нет. Subscription link обновить — добавить `&flow=xtls-rprx-vision`.

---

### C.1 — gRPC через h2c socket

gRPC требует HTTP/2, поэтому нужен второй Unix socket для h2c (HTTP/2 cleartext) — отдельно от h1.sock. Nginx маршрутизирует gRPC-трафик через `grpc_pass` на этот сокет, откуда он попадает в Xray gRPC inbound.

> **Prerequisite перед добавлением gRPC:** добавить `"h2"` в ALPN главного inbound. Без этого HTTP/2-клиенты не согласуют протокол.
>
> ```jsonc
> "tlsSettings": {
>   "alpn": ["h2", "http/1.1"],   // ← было только ["http/1.1"]
>   ...
> }
> ```

#### Новые переменные в `vars.env`

```bash
# --- gRPC inbound ---
GRPC_INBOUND_PORT=9003
GRPC_SERVICE_NAME=your-grpc-service    # произвольное имя, совпадает у сервера и клиента
H2C_SOCK=/dev/shm/xraylab-c-h2c.sock  # отдельный сокет для h2c трафика
```

#### Новый inbound в `xray-server.json.tpl`

```jsonc
{
  "tag": "grpc-in",
  "listen": "127.0.0.1",
  "port": ${GRPC_INBOUND_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id":    "${UUID_VLESS}",
        "email": "user-grpc",
        "level": 0
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "grpc",
    "grpcSettings": {
      "serviceName": "${GRPC_SERVICE_NAME}"
    },
    "security": "none"
  },
  "sniffing": {
    "enabled":      true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly":    true
  }
}
```

#### Новый fallback в главном inbound

```jsonc
"fallbacks": [
  { "path": "${VLESS_WS_PATH}",  "dest": ${VLESS_WS_PORT},  "xver": 1 },
  { "path": "${VMESS_WS_PATH}",  "dest": ${VMESS_WS_PORT},  "xver": 1 },
  { "alpn": "h2",                "dest": "${H2C_SOCK}",      "xver": 1 }, // ← новый
  { "dest": "${H1_SOCK}",                                     "xver": 1 }  // default последним
]
```

#### Nginx: добавить h2c socket listener и gRPC routing

```nginx
# H2C listener (отдельный сокет)
server {
    listen unix:${H2C_SOCK} http2 proxy_protocol;
    set_real_ip_from unix:;
    real_ip_header proxy_protocol;

    location /${GRPC_SERVICE_NAME} {
        if ($request_method != "POST") { return 404; }
        client_body_buffer_size 1m;
        client_body_timeout 1h;
        client_max_body_size 0;
        grpc_read_timeout 1h;
        grpc_send_timeout 1h;
        grpc_pass grpc://127.0.0.1:${GRPC_INBOUND_PORT};
    }

    location / {
        return 404;
    }
}
```

#### Subscription link

```
vless://UUID@DOMAIN:443?security=tls&encryption=none&type=grpc&serviceName=GRPC_SERVICE_NAME&sni=DOMAIN&fp=chrome#C-gRPC-TLS
```

---

### C.2 — VLESS+XHTTP

XHTTP добавляется как ещё один path-based fallback — аналогично WS, но с `xhttp` транспортом.

#### Новые переменные в `vars.env`

```bash
XHTTP_INBOUND_PORT=9004
XHTTP_PATH=/your-xhttp-path
```

#### Новый inbound

```jsonc
{
  "tag": "xhttp-in",
  "listen": "127.0.0.1",
  "port": ${XHTTP_INBOUND_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "${UUID_VLESS}", "email": "user-xhttp", "level": 0 }],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": {
      "path": "${XHTTP_PATH}",
      "mode": "auto",
      "acceptProxyProtocol": true
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
}
```

#### Новый fallback в главном inbound

```jsonc
{ "path": "${XHTTP_PATH}", "dest": ${XHTTP_INBOUND_PORT}, "xver": 1 }
```

Добавить **перед** `alpn:h2` fallback — path-based fallbacks проверяются по порядку.

---

### C.3 — Trojan

Trojan добавляется как отдельный fallback по ALPN или SNI. В отличие от WS/XHTTP — Trojan сам терминирует протокол на уровне sub-inbound, а не по path.

Рекомендуемый вариант — fallback по `alpn: "h2"` с отдельным SNI (нужен второй домен):

```jsonc
// В fallbacks главного inbound:
{ "name": "trojan.your-domain.com", "alpn": "h2", "dest": ${TROJAN_PORT}, "xver": 1 }
```

```jsonc
// Новый Trojan inbound:
{
  "tag": "trojan-in",
  "listen": "127.0.0.1",
  "port": ${TROJAN_PORT},
  "protocol": "trojan",
  "settings": {
    "clients": [{ "password": "${TROJAN_PASSWORD}", "email": "user-trojan", "level": 0 }],
    "fallbacks": [{ "dest": "${H1_SOCK}", "xver": 1 }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "none",
    "rawSettings": { "acceptProxyProtocol": true }
  }
}
```

---

### C.4 — Shadowsocks

Shadowsocks не использует path-routing — это отдельный self-contained inbound на другом порту. Не требует изменений в fallbacks.

```jsonc
{
  "tag": "ss-in",
  "listen": "0.0.0.0",
  "port": ${SS_PORT},
  "protocol": "shadowsocks",
  "settings": {
    "method":   "2022-blake3-aes-128-gcm",
    "password": "${SS_PASSWORD}",
    "network":  "tcp,udp"
  }
}
```

```bash
# Открыть порт
ufw allow ${SS_PORT}/tcp
ufw allow ${SS_PORT}/udp

# Генерация ключа SS2022 (16 байт для aes-128)
openssl rand -base64 16
```

---

### Итоговая картина Variant C

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+TLS+Vision (main inbound, ALPN: h2 + http/1.1)
    │
    ├── path=/VLESS_WS_PATH      →  :9001  VLESS+WS
    ├── path=/VMESS_WS_PATH      →  :9002  VMess+WS
    ├── path=/XHTTP_PATH         →  :9004  VLESS+XHTTP
    ├── alpn=h2 + SNI=trojan.*   →  :9005  Trojan+TCP
    ├── alpn=h2 (other)          →  H2C_SOCK → Nginx → :9003  VLESS+gRPC
    └── default                  →  H1_SOCK  → Nginx decoy + /sub

Internet :SS_PORT (TCP+UDP) → Shadowsocks 2022
```

| Tag | Протокол | Транспорт | Путь входа |
|---|---|---|---|
| C-VLESS | VLESS + Vision | TCP+TLS | DOMAIN:443 (прямой) |
| C-WS | VLESS | WebSocket+TLS | :443/VLESS_WS_PATH |
| C-VMess | VMess | WebSocket+TLS | :443/VMESS_WS_PATH |
| C-XHTTP | VLESS | XHTTP+TLS | :443/XHTTP_PATH |
| C-gRPC | VLESS | gRPC+TLS | :443, h2c sock |
| C-Trojan | Trojan | TCP+TLS | :443, alpn=h2 + SNI |
| C-SS | Shadowsocks 2022 | TCP+UDP | :SS_PORT |

---

---

## Variant D — Self-SNI (VLESS+Vision+TLS, собственный decoy)

### Текущее состояние

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+TLS+Vision (main inbound)
    └── default fallback → 127.0.0.1:NGINX_DECOY_PORT
                               └── Nginx: decoy сайт + /sub
Internet :80 → Nginx: 301 → HTTPS
```

Один протокол, один fallback. Nginx работает на TCP-порту — в отличие от Variant C, где Nginx на Unix socket.

### Чем D отличается от C

| | Variant D | Variant C |
|---|---|---|
| Xray терминирует TLS | ✅ | ✅ |
| Vision flow | ✅ с самого начала | добавляется в C.0 |
| Nginx decoy | TCP-порт `127.0.0.1:DECOY_PORT` | Unix socket `H1_SOCK` |
| Легенда сервера | ✅ домен = сертификат = IP = сайт | ⚡ decoy без согласованной легенды |
| Reality | ❌ | ❌ |
| Стартовая сложность | Низкая | Средняя |

Добавление протоколов постепенно сближает D с C. Принципиальное различие остаётся одно: декой-сайт D на TCP-порту выглядит как настоящий веб-сервер с точки зрения сканеров (там реальный HTML, реальный HSTS), тогда как Unix socket C снаружи вообще не виден.

### Потолок архитектуры D

Как и C, Variant D не может включать Reality — оба используют `fallbacks`, несовместимые с Reality. Если понадобится Reality рядом с TLS-протоколами, нужен переход на Variant B (Nginx stream как роутер).

---

### D.1 — VLESS+WS fallback

Первое расширение: path-based fallback на WebSocket inbound. Механика идентична Variant C, но Nginx уже запущен на TCP-порту — новый `location` добавляется в существующий server block.

#### Новые переменные в `vars.env`

```bash
UUID_WS=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy   # make keys
WS_PORT=9001
WS_PATH=/your-ws-path
```

#### Новый inbound в `xray-server.json.tpl`

```jsonc
{
  "tag": "vless-ws-in",
  "listen": "127.0.0.1",
  "port": ${WS_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [
      { "id": "${UUID_WS}", "email": "user-ws", "level": 0 }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "wsSettings": {
      "path": "${WS_PATH}",
      "acceptProxyProtocol": true
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
}
```

#### Обновить fallbacks в главном inbound

```jsonc
"fallbacks": [
  { "path": "${WS_PATH}", "dest": ${WS_PORT}, "xver": 1 },  // ← добавить
  { "dest": ${NGINX_DECOY_PORT} }                            // default — последним
]
```

#### Обновить `nginx.conf.tpl` — добавить location в decoy server block

```nginx
server {
    listen 127.0.0.1:${NGINX_DECOY_PORT};
    ...

    location ${WS_PATH} {
        if ($http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:${WS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        real_ip_header proxy_protocol;   # раскомментировать если xver: 1
    }

    location / { ... }   // decoy — без изменений
}
```

#### Subscription link

```
vless://UUID_WS@DOMAIN:443?security=tls&encryption=none&type=ws&path=WS_PATH&sni=DOMAIN&fp=chrome#D-WS-TLS
```

---

### D.2 — VMess+WS fallback

Аналогично D.1 — второй path-based fallback. Добавить в `vars.env`:

```bash
UUID_VMESS=zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz
VMESS_PORT=9002
VMESS_PATH=/your-vmess-path
```

Структура inbound та же, что у D.1, с заменой `protocol: "vmess"` и `UUID_VMESS`. VMess не использует `decryption`, вместо этого у клиентов есть встроенное шифрование.

Добавить fallback перед default:
```jsonc
{ "path": "${VMESS_PATH}", "dest": ${VMESS_PORT}, "xver": 1 }
```

Добавить `location ${VMESS_PATH}` в Nginx по той же схеме что WS.

---

### D.3 — VLESS+XHTTP fallback

XHTTP предпочтительнее WS — разделяет upload/download на отдельные HTTP-запросы, что затрудняет корреляцию трафика. Добавлять после D.1–D.2, либо вместо WS если CDN поддерживает XHTTP.

```bash
UUID_XHTTP=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
XHTTP_PORT=9003
XHTTP_PATH=/your-xhttp-path
```

Inbound:
```jsonc
{
  "tag": "xhttp-in",
  "listen": "127.0.0.1",
  "port": ${XHTTP_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "${UUID_XHTTP}", "email": "user-xhttp", "level": 0 }],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "xhttpSettings": { "path": "${XHTTP_PATH}", "mode": "auto", "acceptProxyProtocol": true }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
}
```

Fallback (добавить перед `alpn:h2` если он уже есть, и перед default):
```jsonc
{ "path": "${XHTTP_PATH}", "dest": ${XHTTP_PORT}, "xver": 1 }
```

Nginx location:
```nginx
location ${XHTTP_PATH} {
    proxy_pass http://127.0.0.1:${XHTTP_PORT};
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

---

### D.4 — gRPC через h2c (с ALPN prerequisite)

gRPC требует HTTP/2. В Variant D Nginx работает на TCP-порту — для h2c добавляем отдельный Unix socket, аналогично Variant C. Это аккуратнее чем смешивать HTTP/1.1 и h2c на одном listener.

> **Prerequisite:** добавить `"h2"` в ALPN главного inbound **перед** этим шагом.
>
> ```jsonc
> "tlsSettings": {
>   "fingerprint": "chrome",
>   "alpn": ["h2", "http/1.1"],   // ← было только ["http/1.1"]
>   ...
> }
> ```

#### Новые переменные в `vars.env`

```bash
UUID_GRPC=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
GRPC_PORT=9004
GRPC_SERVICE_NAME=your-grpc-service
H2C_SOCK=/dev/shm/xraylab-d-h2c.sock
```

#### Новый fallback в главном inbound

```jsonc
"fallbacks": [
  { "path": "${WS_PATH}",   "dest": ${WS_PORT},   "xver": 1 },
  { "path": "${VMESS_PATH}","dest": ${VMESS_PORT}, "xver": 1 },
  { "path": "${XHTTP_PATH}","dest": ${XHTTP_PORT}, "xver": 1 },
  { "alpn": "h2",           "dest": "${H2C_SOCK}", "xver": 1 }, // ← gRPC
  { "dest": ${NGINX_DECOY_PORT} }
]
```

#### Новый gRPC inbound

```jsonc
{
  "tag": "grpc-in",
  "listen": "127.0.0.1",
  "port": ${GRPC_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "${UUID_GRPC}", "email": "user-grpc", "level": 0 }],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "grpc",
    "grpcSettings": { "serviceName": "${GRPC_SERVICE_NAME}" },
    "security": "none"
  }
}
```

#### Nginx: добавить h2c Unix socket listener

В `nginx.conf.tpl` добавить отдельный server block рядом с существующим decoy:

```nginx
# Существующий decoy server (без изменений):
server {
    listen 127.0.0.1:${NGINX_DECOY_PORT};
    ...
}

# Новый h2c listener для gRPC:
server {
    listen unix:${H2C_SOCK} http2 proxy_protocol;
    set_real_ip_from unix:;
    real_ip_header proxy_protocol;

    location /${GRPC_SERVICE_NAME} {
        if ($request_method != "POST") { return 404; }
        client_body_buffer_size 1m;
        client_body_timeout 1h;
        client_max_body_size 0;
        grpc_read_timeout 1h;
        grpc_send_timeout 1h;
        grpc_pass grpc://127.0.0.1:${GRPC_PORT};
    }

    location / { return 404; }
}
```

#### Subscription link

```
vless://UUID_GRPC@DOMAIN:443?security=tls&encryption=none&type=grpc&serviceName=GRPC_SERVICE_NAME&sni=DOMAIN&fp=chrome#D-gRPC-TLS
```

---

### Итоговая картина Variant D

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+TLS+Vision (ALPN: h2 + http/1.1)
    │
    ├── path=/WS_PATH     →  :9001  VLESS+WS        → Nginx proxy_pass
    ├── path=/VMESS_PATH  →  :9002  VMess+WS         → Nginx proxy_pass
    ├── path=/XHTTP_PATH  →  :9003  VLESS+XHTTP      → Nginx proxy_pass
    ├── alpn=h2           →  H2C_SOCK → Nginx → :9004 VLESS+gRPC
    └── default           →  127.0.0.1:DECOY_PORT
                                └── Nginx: decoy сайт + /sub (HTTP/1.1)

Internet :80 → Nginx: 301 redirect → HTTPS
```

| Tag | Протокол | Транспорт | Путь входа |
|---|---|---|---|
| D-main | VLESS + Vision | TCP+TLS | DOMAIN:443 (прямой) |
| D-WS | VLESS | WebSocket+TLS | :443/WS_PATH |
| D-VMess | VMess | WebSocket+TLS | :443/VMESS_PATH |
| D-XHTTP | VLESS | XHTTP+TLS | :443/XHTTP_PATH |
| D-gRPC | VLESS | gRPC+TLS | :443, alpn=h2, h2c sock |

### Где D сходится с C

После шага D.4 архитектура D и C практически идентичны — оба используют Xray как TLS terminator с деревом fallbacks и Nginx на Unix socket для h2c. Принципиальных различий два:

- D сохраняет согласованную легенду: decoy-сайт на реальном TCP-порту, куда можно зайти браузером и получить настоящий HTML с HSTS
- D не использует Unix socket для HTTP/1.1 decoy — Nginx виден как настоящий веб-сервер

Если после всех расширений понадобится Reality рядом с этими протоколами — это уже **Variant B** (Nginx stream как SNI router).

---

## Порядок тестирования

Каждый шаг — отдельный коммит, отдельный запуск `make test`:

```
B: fix dest→target          # hotfix, не новый протокол

A: + mKCP                   # новый inbound, нет зависимостей

B: + XHTTP+TLS              # Nginx location + новый inbound
B: + mKCP                   # независимый UDP inbound
B: + nested K               # fallback в существующий XHTTP inbound
B: + HTTP/3 UDP:443         # только Nginx, Xray не трогаем

C: Vision flow              # только поле в конфиге
C: ALPN prereq h2           # перед gRPC
C: + gRPC (h2c sock)        # самый сложный шаг в C
C: + XHTTP                  # path fallback
C: + Trojan                 # alpn/SNI fallback
C: + Shadowsocks            # независимый inbound

D: + VLESS+WS               # path fallback + Nginx location
D: + VMess+WS               # то же
D: + VLESS+XHTTP            # path fallback + Nginx location
D: ALPN prereq h2           # перед gRPC
D: + gRPC (h2c sock)        # h2c Unix socket + Nginx block
```
