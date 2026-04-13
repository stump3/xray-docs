# Xray VPN на одном порту 443
## Сравнительный анализ архитектур, протоколов и схем развёртывания

> Техническая документация для инженерной команды · апрель 2026

---

## 1. Контекст и цели

Задача: развернуть VPN-сервер на базе Xray с максимальной гибкостью — все протоколы слушают единственный внешний порт 443, Nginx при необходимости хостит сайт/панель/subscription-ссылки на произвольном порту, архитектура расширяема на будущее.

**Ключевые требования:**

- Все прокси-протоколы — на порту 443 (единственный разрешённый/незаблокированный)
- Nginx-порт выбирается произвольно: инженер решает сам
- Возможность добавить панель управления (Marzban / 3x-ui) в будущем
- Поддержка subscription links для мобильных клиентов
- Устойчивость к DPI и active probing

> ⚠️ **Фундаментальное ограничение:** На одном TCP-порту может висеть ровно один процесс. Для совместного размещения нескольких сервисов на 443 необходим либо роутер (Nginx stream / HAProxy), либо Xray принимает всё на 443 и сам маршрутизирует внутри.

---

## 2. Протоколы и транспорты: сравнительная таблица

| Транспорт | Через CDN | Обнаружение | Скорость | Нужен сертификат | Сложность |
|---|---|---|---|---|---|
| XTLS-Reality (TCP+RAW) | ❌ нет | Очень низкое | Высокая | ❌ нет | Низкая |
| XHTTP + Reality | ❌ нет | Очень низкое | Высокая | ❌ нет | Средняя |
| XHTTP + Reality + TLS (套娃) | ❌ нет | Очень низкое | Высокая | ❌ нет | Высокая |
| XTLS-Vision + TLS | ❌ нет | Низкое | Высокая | ✅ да | Средняя |
| Trojan + RAW + TLS | ❌ нет | Низкое | Высокая | ✅ да | Средняя |
| VLESS + XHTTP + TLS | ✅ да | Низкое | Высокая | ✅ да | Средняя |
| VLESS + HTTPUpgrade + TLS | ✅ да | Среднее | Средняя | ✅ да | Низкая |
| VLESS + WebSocket + TLS | ✅ да | Среднее | Средняя | ✅ да | Низкая |
| VLESS + gRPC + TLS | ✅ да | Низкое | Средняя | ✅ да | Средняя |
| VLESS + gRPC + Reality | ❌ нет | Низкое | Средняя | ❌ нет | Средняя |
| VLESS + mKCP + seed | ❌ нет | Среднее | Высокая (UDP) | ❌ нет | Низкая |
| VMess + XHTTP + TLS | ✅ да | Низкое | Высокая | ✅ да | Средняя |
| VMess + WebSocket + TLS | ✅ да | Среднее | Средняя | ✅ да | Низкая |

> ℹ️ **Про Reality:** Reality работает на уровне TLS handshake — Xray читает ClientHello и если клиент «свой» работает как прокси, иначе передаёт соединение на реальный сайт (например, microsoft.com). Клиент получает настоящий TLS-сертификат microsoft.com, что делает active probing бессмысленным. Сертификат на сервере не нужен. **Reality несовместима с механизмом fallbacks** — они работают на разных уровнях стека.

> ℹ️ **Про XHTTP (SplitHTTP):** Xray v24.11.30+ реализует полное разделение upload/download потоков. Upload идёт отдельными POST-запросами, download — chunked response. Это существенно затрудняет анализ трафика по временны́м паттернам одного TCP-соединения. Транспорт поддерживает как TLS, так и Reality (в том числе в режиме «套娃» — XHTTP поверх REALITY через внешний VLESS+Vision inbound).

> ℹ️ **Про mKCP:** UDP-транспорт, не использует порт 443. Работает на отдельном порту (например, 2052). Не проксируется CDN. Эффективен там, где UDP-трафик не заблокирован — даёт высокую пропускную способность при потерях пакетов.

---

## 3. Архитектуры маршрутизации: четыре подхода

### 3.1 Вариант A — Xray напрямую на 443 (без роутера)

Xray занимает порт 443 целиком. Nginx работает независимо на произвольном TCP-порту (8080, 3000, 7443 — любой выбор инженера). Между ними нет связи.

```
Порт 443  →  Xray (Reality или XHTTP+Reality)
Порт 8080 →  Nginx (сайт, sub-link, панель)  ← порт выбирается произвольно
```

**Nginx конфиг:**

```nginx
server {
    listen 8080;  # ← любой порт по выбору инженера
    server_name _;
    root /var/www/html;
    location /sub { alias /var/www/sub/; }
}
```

**Xray server config (XHTTP+Reality, официальный minimal пример):**

```json
{
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "UUID", "flow": "" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "xhttp",
      "xhttpSettings": { "path": "/yourpath" },
      "security": "reality",
      "realitySettings": {
        "target": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "PRIVATE-KEY",
        "shortIds": ["00", "01", "02"]
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls", "quic"]
    }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
```

| ✅ Плюсы | ❌ Минусы |
|---|---|
| Максимальная простота | Только Reality — WS/gRPC через CDN не добавить без роутера |
| Nginx-порт абсолютно свободен | Сайт на 443 не разместить одновременно с Xray |
| Нет промежуточного слоя | Subscription endpoint только на другом порту |

---

### 3.2 Вариант B — Nginx stream (SNI routing)

Nginx занимает порт 443, читает SNI из ClientHello ещё до TLS handshake и маршрутизирует TCP-поток. Xray и сайт слушают на внутренних портах. Порты выбираются произвольно.

```
Порт 443  →  Nginx stream (читает SNI)
              ├── SNI = your-domain.com  →  Nginx HTTPS :7443  (сайт + WS proxy)
              │                                └── location /ws  →  Xray WS inbound :9001
              └── SNI = всё остальное   →  Xray Reality :8443
```

**Nginx stream конфиг** (`/etc/nginx/nginx.conf`, блок stream):

```nginx
stream {
    map $ssl_preread_server_name $backend {
        your-domain.com    nginx_https;
        default            xray_reality;
    }
    upstream xray_reality { server 127.0.0.1:8443; }
    upstream nginx_https  { server 127.0.0.1:7443; }  # ← ваш выбор

    server {
        listen 443;
        ssl_preread on;
        proxy_pass $backend;
    }
}
```

**Nginx HTTPS server block** (порт — ваш выбор):

```nginx
server {
    listen 7443 ssl;  # ← меняете здесь и в upstream выше
    server_name your-domain.com;
    ssl_certificate     /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    root /var/www/html;
    location /sub { alias /var/www/sub/; default_type text/plain; }

    # WS → Xray WS inbound
    location /vless-ws {
        proxy_pass http://127.0.0.1:9001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

**Xray config с двумя inbound** (Reality + WS):

```json
{
  "inbounds": [
    {
      "tag": "reality-in",
      "listen": "127.0.0.1",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "UUID-REALITY", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "PRIVATE-KEY",
          "shortIds": ["YOUR-SHORT-ID"]
        }
      }
    },
    {
      "tag": "ws-in",
      "listen": "127.0.0.1",
      "port": 9001,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "UUID-WS" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vless-ws" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
```

> ⚠️ **Проблема реальных IP:** При использовании Nginx stream реальные IP пользователей в логах заменяются на 127.0.0.1. Решается через `proxy_protocol`: Nginx добавляет заголовок с реальным IP при передаче трафику, второй listener снимает заголовок перед Xray (т.к. Reality его не поддерживает). Альтернатива — HAProxy с директивой `send-proxy`.

| ✅ Плюсы | ❌ Минусы |
|---|---|
| Reality + WS/CDN на одном порту 443 | Нужен stream-модуль Nginx |
| Nginx-порт полностью на выбор инженера | Дополнительный hop (задержка ~0.1ms) |
| Легко добавить новые протоколы (новый upstream) | IP-проблема требует proxy_protocol |
| Привычный Nginx, хорошая документация | HAProxy — альтернатива, ещё один демон |

---

### 3.3 Вариант C — Xray native fallbacks (All-in-One, официальный)

Xray занимает порт 443 целиком и сам управляет TLS. После расшифровки смотрит на path/ALPN/SNI и передаёт соединение внутренним inbound через Unix-сокеты. Nginx нужен только для decoy-сайта и gRPC — и слушает на Unix-сокетах (без TCP-порта вообще).

```
Порт 443  →  Xray VLESS+TLS (главный inbound, делает TLS-терминацию)
              │  Читает path / ALPN / SNI после расшифровки
              ├── path=/vlws        →  @vless-ws   (unix socket)
              ├── path=/vmws        →  @vmess-ws   (unix socket)
              ├── path=/vltc        →  @vless-tcp  (unix socket)
              ├── alpn=h2 + SNI=X   →  @trojan-h2  (unix socket)
              ├── alpn=h2 (generic) →  @trojan-tcp → /dev/shm/h2c.sock (Nginx gRPC)
              └── default           →  /dev/shm/h1.sock  (Nginx decoy сайт, HTTP/1.1)

Nginx слушает:
  /dev/shm/h1.sock   (HTTP/1.1 для decoy-сайта, без TCP-порта)
  /dev/shm/h2c.sock  (HTTP/2 cleartext для gRPC routing)
```

**Ключевые особенности:**

- Xray обрабатывает TLS — нужен реальный сертификат (Let's Encrypt или аналог)
- Все sub-inbound общаются через Unix-сокеты: `@vless-ws`, `@trojan-tcp` и т.д.
- PROXY protocol (`xver: 2`) в fallbacks передаёт реальный IP во все sub-inbound
- gRPC идёт через Nginx h2c (cleartext HTTP/2)
- Nginx TCP-порт не нужен вообще

**Фрагмент конфига — главный inbound с fallbacks:**

```json
{
  "tag": "Vless-TCP-TLS",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "UUID", "flow": "xtls-rprx-vision" }],
    "decryption": "none",
    "fallbacks": [
      { "path": "/vlws", "dest": "@vless-ws",  "xver": 2 },
      { "path": "/vmws", "dest": "@vmess-ws",  "xver": 2 },
      { "path": "/vltc", "dest": "@vless-tcp", "xver": 2 },
      { "alpn": "h2",    "dest": "@trojan-tcp","xver": 2 },
      { "dest": "/dev/shm/h1.sock", "xver": 2 }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "certificates": [{
        "certificateFile": "/etc/letsencrypt/live/domain.com/fullchain.pem",
        "keyFile":         "/etc/letsencrypt/live/domain.com/privkey.pem"
      }],
      "alpn": ["h2", "http/1.1"]
    }
  }
}
```

> ⚠️ **Критически важно: Reality несовместима с fallbacks.** Reality работает на уровне TLS handshake до расшифровки. Fallbacks работают после расшифровки. Их невозможно совместить на одном inbound. Варианты C (fallbacks) и Reality — взаимоисключающие подходы.

| ✅ Плюсы | ❌ Минусы |
|---|---|
| Максимальное число протоколов на 443 | Нужен TLS-сертификат (Let's Encrypt) |
| Реальные IP работают из коробки (xver: 2) | Reality недоступна в этой схеме |
| Nginx без TCP-порта — нет конфликтов | Более сложная отладка (unix sockets) |
| Официальный рекомендуемый подход (Xray-examples) | При ошибке конфига весь 443 падает |

---

### 3.4 Вариант D — Self-SNI: Xray+TLS с маскировкой под собственный сайт

Xray занимает порт 443 целиком и терминирует TLS с **собственным** сертификатом (Let's Encrypt). Нераспознанный трафик падает через единственный fallback на `127.0.0.1:8080`, где Nginx отдаёт **реальный сайт на том же сервере**. При прямом запросе по домену клиент получает настоящую HTML-страницу с валидным TLS-сертификатом именно этого домена — сервер визуально неотличим от легитимного веб-хостинга.

**Ключевое отличие от Reality:** в Reality декой — сторонний сайт (например, microsoft.com), расположенный на другом IP. Active probing цензора может выявить несоответствие: IP сервера ≠ IP microsoft.com. В Self-SNI декой — собственный сайт на том же IP, что и домен. Домен, сертификат, сайт и IP образуют полностью согласованную картину.

**Ключевое отличие от Варианта C:** Вариант C использует дерево fallbacks на множество протоколов через Unix-сокеты. Вариант D — один примитивный fallback на Nginx, один транспорт (VLESS+Vision), нет Unix-сокетов. Акцент не на количестве протоколов, а на максимальной достоверности легенды сервера.

```
Порт 443  →  Xray VLESS+TCP+TLS (собственный сертификат домена)
              │  flow: xtls-rprx-vision, fp: chrome, ALPN: http/1.1
              ├── Клиент «свой» (VLESS+Vision) → прокси-трафик
              └── Всё остальное (HTTP, probing) → fallback → 127.0.0.1:8080
                                                               │
                                                         Nginx (decoy сайт)

Порт 80   →  Nginx (301 redirect → HTTPS)
```

**Xray config:**

```json
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "email": "main", "id": "UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none",
      "fallbacks": [{ "dest": 8080 }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls",
      "tlsSettings": {
        "fingerprint": "chrome",
        "alpn": "http/1.1",
        "certificates": [{
          "certificateFile": "/usr/local/etc/xray/xray_cert/xray.crt",
          "keyFile":         "/usr/local/etc/xray/xray_cert/xray.key"
        }]
      }
    }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
```

**Nginx конфиг:**

```nginx
# HTTP → HTTPS redirect
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$http_host$request_uri;
}

# Decoy сайт — только localhost, снаружи напрямую недоступен
server {
    listen 127.0.0.1:8080;
    server_name your-domain.com;
    root /var/www/html/;
    index index.html;
    add_header Strict-Transport-Security "max-age=63072000" always;
}
```

**Сертификат — acme.sh + ECDSA ec-256:**

```bash
export domain=your-domain.com

~/.acme.sh/acme.sh --issue --server letsencrypt \
    -d $domain -w /var/www/html --keylength ec-256 --force

~/.acme.sh/acme.sh --install-cert -d $domain --ecc \
    --fullchain-file /usr/local/etc/xray/xray_cert/xray.crt \
    --key-file       /usr/local/etc/xray/xray_cert/xray.key

chmod +r /usr/local/etc/xray/xray_cert/xray.key
```

Автопродление: скрипт `/usr/local/etc/xray/xray_cert/xray-cert-renew` + cron `0 1 1 * *`.

**Subscription link (VLESS+TCP+TLS+Vision):**

```
vless://UUID@your-domain.com:443
  ?security=tls
  &alpn=http%2F1.1
  &fp=chrome
  &type=tcp
  &flow=xtls-rprx-vision
  &spx=/
  &encryption=none
  #username
```

**CLI-инструменты управления (устанавливаются скриптом в `/usr/local/bin/`):**

| Команда | Действие |
|---|---|
| `mainuser` | Ссылка + QR-код основного пользователя |
| `newuser` | Интерактивное создание нового пользователя |
| `rmuser` | Удаление пользователя из списка |
| `sharelink` | Ссылка + QR-код для выбранного пользователя |
| `userlist` | Список всех клиентов |

> ⚠️ **Ограничение: только один транспорт.** В Варианте D нет WS, gRPC или других транспортов — только VLESS+TCP+Vision. CDN (Cloudflare) несовместима с xtls-rprx-vision. Добавление дополнительных протоколов требует перехода на Вариант B или C.

> ℹ️ **Совместимость с панелями.** Конфиг inbound для Marzban и 3x-ui идентичен: VLESS+TCP+TLS, ALPN http/1.1, fallback → 8080, flow xtls-rprx-vision. Nginx настраивается так же. Панель заменяет только CLI-инструменты управления пользователями.

| ✅ Плюсы | ❌ Минусы |
|---|---|
| Максимальная достоверность декоя — домен + сертификат + IP согласованы | Нужен домен и TLS-сертификат |
| Active probing видит реальный сайт с валидным сертификатом именно этого IP | Reality недоступна в этой схеме |
| Реальные IP нативно (Xray терминирует TLS) | Только один транспорт (VLESS+Vision), нет WS/gRPC |
| Минимальная сложность: один fallback, нет Unix-сокетов и stream-роутера | CDN-совместимость отсутствует |
| Простой автоматизированный деплой одним bash-скриптом | Нет subscription endpoint из коробки |
| Поддержка Marzban / 3x-ui без изменения архитектуры | — |

---

## 4. Итоговая матрица выбора архитектуры

| Требование / Сценарий | Вариант A (Xray на 443) | Вариант B (Nginx stream) | Вариант C (Fallbacks) | Вариант D (Self-SNI) |
|---|---|---|---|---|
| Только Reality, минимум сложности | ✅ Идеально | ⚡ Работает | ❌ Недоступно | ❌ Недоступно |
| Reality + WS/gRPC через CDN на одном 443 | ❌ Нет | ✅ Идеально | ❌ Нет | ❌ Нет |
| Nginx-порт выбирается произвольно | ✅ Полностью | ✅ Да (upstream) | ✅ Unix socket | ✅ Да (8080 → любой) |
| Максимум протоколов на 443 | ⚡ Один | ⚡ 2–3 | ✅ Десятки | ⚡ Один |
| Сайт на 443 одновременно с прокси | ❌ Нет | ✅ Да | ✅ Да | ✅ Да (через fallback) |
| Панель управления (Marzban/3x-ui) | ⚡ На отдельном порту | ✅ На 443 через SNI | ✅ Через fallback | ✅ Marzban/3x-ui |
| Subscription endpoint | ✅ На отдельном порту | ✅ На 443 под доменом | ✅ Через fallback | ⚡ Через доп. location Nginx |
| Реальные IP в логах | ✅ Нативно | ⚠️ proxy_protocol | ✅ xver: 2 | ✅ Нативно |
| Нужен TLS-сертификат | ❌ Нет | ✅ Да (для домена) | ✅ Обязателен | ✅ Обязателен |
| Active probing устойчивость | ✅ Reality (3rd party) | ✅ Reality (3rd party) | ⚡ Decoy сайт (сторонний IP) | ✅ Decoy сайт (свой IP) |
| Сложность первоначальной настройки | Низкая | Средняя | Высокая | Низкая |

---

## 5. Официальные примеры (Xray-examples)

Репозиторий содержит эталонные конфигурации. Все директории:

| Директория | Описание |
|---|---|
| `VLESS-XHTTP-Reality/` | VLESS + XHTTP-транспорт + Reality. Минимальный конфиг, Xray напрямую на 443. Официально рекомендуется как наиболее скрытный вариант без сертификата. |
| `VLESS-WSS-Nginx/` | VLESS + WebSocket + TLS. Nginx на 443, проксирует WS-путь на Xray. CDN-совместимо. |
| `VLESS-gRPC-REALITY/` | VLESS + gRPC + Reality. Xray на порту 80 (в примере). Нет Nginx. |
| `All-in-One-fallbacks-Nginx/` | Vless-TCP-TLS как точка входа с fallbacks на все протоколы: WS, gRPC, H2, TCP. Nginx на unix-сокетах. Наиболее полная конфигурация, содержит `generate.sh` для автоматизации. |
| `VLESS-TLS-SplitHTTP-CaddyNginx/` | VLESS + SplitHTTP/XHTTP + TLS через Caddy или Nginx. Альтернатива для CDN. |
| `VLESS-XHTTP3-Nginx/` | VLESS + XHTTP + HTTP/3 (QUIC). Nginx на 443, клиент поддерживает h3. |
| `Trojan-gRPC-Caddy2/Nginx/` | Trojan + gRPC через Caddy или Nginx. Альтернатива VLESS для Trojan-клиентов. |
| `ReverseProxy/` | Схемы обратного прокси: bridge → portal. Для случаев когда сервер не имеет прямого доступа в интернет. |
| `Serverless-for-Iran/` | Конфигурации для работы через serverless-платформы (Cloudflare Workers и т.п.). |
| `MITM-Domain-Fronting/` | Продвинутая схема с подменой домена для обхода SNI-фильтрации. |

> ℹ️ **All-in-One generate.sh:** Директория `All-in-One-fallbacks-Nginx` содержит скрипт `generate.sh`. Он автоматически заменяет все placeholder-значения (домен, UUID, пароль, пути), генерирует subscription-ссылки в `result.txt` и QR-коды. Запуск: `-m` (применить), `-b` (base64 всех ссылок), `-q` (QR-коды), `-r` (откат).

---

## 6. Генерация ключей и идентификаторов

| Ключ | Команда | Куда вставлять |
|---|---|---|
| UUID клиента | `/opt/xray/xray uuid` | `clients[].id` на сервере и клиенте |
| Private key (сервер) | `/opt/xray/xray x25519` → строка `Private key` | `realitySettings.privateKey` на сервере |
| Public key (клиент) | `/opt/xray/xray x25519` → строка `Public key` | `realitySettings.publicKey` на клиенте |
| Short ID | `openssl rand -hex 8` | `realitySettings.shortIds[]` на сервере, `shortId` на клиенте |

> ⚠️ **Безопасность:** Private key и UUID — секретные данные. Публичный ключ и Short ID передаются клиентам. Приватный ключ никогда не покидает сервер. Генерируйте отдельную пару ключей на каждый сервер.

---

## 7. Subscription links и клиентская конфигурация

Для быстрой настройки мобильных клиентов (Shadowrocket, v2rayN, NekoBox, Hiddify) используются URI-ссылки, которые можно конвертировать в QR-коды.

### VLESS + XHTTP + Reality

```
vless://UUID@SERVER-IP:443
  ?security=reality
  &encryption=none
  &pbk=PUBLIC-KEY
  &fp=chrome
  &type=xhttp
  &path=/yourpath
  &sni=www.microsoft.com
  &sid=SHORT-ID
  #имя-профиля
```

### VLESS + TCP + XTLS-Vision + Reality

```
vless://UUID@SERVER-IP:443
  ?security=reality
  &encryption=none
  &pbk=PUBLIC-KEY
  &fp=chrome
  &type=tcp
  &flow=xtls-rprx-vision
  &sni=www.microsoft.com
  &sid=SHORT-ID
  #имя-профиля
```

### VLESS + TCP + XTLS-Vision + TLS (Self-SNI, Вариант D)

```
vless://UUID@your-domain.com:443
  ?security=tls
  &encryption=none
  &fp=chrome
  &alpn=http%2F1.1
  &type=tcp
  &flow=xtls-rprx-vision
  &spx=/
  #имя-профиля
```

### VLESS + WebSocket + TLS (CDN-совместимый)

```
vless://UUID@your-domain.com:443
  ?security=tls
  &encryption=none
  &type=ws
  &path=/vless-ws
  &sni=your-domain.com
  #имя-профиля
```

### Subscription endpoint

Текстовый файл с несколькими ссылками (по одной на строку), base64-закодированный. Клиент периодически его опрашивает и обновляет список серверов.

```bash
# /var/www/sub/config.txt
vless://UUID1@server1:443?...#Server-1-Reality
vless://UUID2@server1:443?...#Server-1-WS

# Кодируем для клиентов:
base64 -w 0 /var/www/sub/config.txt > /var/www/sub/encoded
# Клиент получает: https://your-domain.com/sub/encoded
```

---

## 8. Панели управления

Панели автоматизируют управление пользователями, генерируют Xray-конфиги и subscription-ссылки. При использовании панели Nginx нужен только как reverse proxy перед её веб-интерфейсом — ручной `config.json` не нужен.

| Панель | Стек | Reality | WS/gRPC | Self-SNI (D) | Sub-links |
|---|---|---|---|---|---|
| Marzban | Python / FastAPI | ✅ | ✅ | ✅ | ✅ |
| 3x-ui | Go | ✅ | ✅ | ✅ | ✅ |
| X-UI (оригинал) | Go | ⚡ Ограничено | ✅ | ✅ | ✅ |
| Чистый Xray | — | ✅ Полный контроль | ✅ Полный контроль | ✅ Полный контроль | Вручную |

---

## 9. Особенности CDN: WebSocket и gRPC

Reality и Vision работают только при прямом IP-подключении — CDN не может их проксировать. WebSocket и gRPC через Cloudflare работают.

| | Reality / Vision | WS или gRPC + TLS | Self-SNI (Vision) |
|---|---|---|---|
| Через CDN (Cloudflare) | ❌ Невозможно | ✅ Работает | ❌ Невозможно |
| Блокировка IP сервера | Уязвимо | ✅ CDN-IP не блокируют | Уязвимо |
| CDN видит трафик | Неприменимо | ⚠️ Cloudflare — MitM | Неприменимо |
| Скрытность от DPI | Максимальная | Средняя (WS) / Хорошая (gRPC) | Высокая |
| Active probing | ✅ 3rd-party decoy | ⚡ Зависит от конфига | ✅ Own-site decoy |

Для Cloudflare WebSocket: в Dashboard → Network включить WebSocket. Для gRPC: включить gRPC в Network.

---

## 10. Рекомендуемая финальная архитектура

На основе анализа всех вариантов — рекомендуемая схема для развёртывания с максимальной гибкостью:

```
Internet :443 (TCP)
    │
    ▼
Nginx stream (SNI routing)  ← /etc/nginx/nginx.conf, блок stream
    │
    ├── SNI = your-domain.com  ──→  Nginx HTTPS :7443
    │                                  ├── /         → decoy-сайт
    │                                  ├── /sub      → subscription endpoint
    │                                  ├── /panel    → панель (Marzban/3x-ui)
    │                                  └── /vless-ws → Xray WS inbound :9001
    │
    └── SNI = всё остальное  ──→  Xray Reality :8443
                                     └── VLESS+XHTTP+Reality
```

**Обоснование выбора Nginx stream (Вариант B):**

- Reality остаётся доступна — максимальная скрытность для прямых клиентов
- WS/gRPC через CDN на том же 443 — для клиентов в странах с жёсткой фильтрацией
- Nginx-порт (7443 в примере) меняется в двух местах: `upstream` + `listen` — полный контроль инженера
- Subscription endpoint на домене через HTTPS — клиенты обновляют конфиги автоматически
- Панель управления добавляется как `location /panel` в Nginx без изменения Xray-конфига
- Реальные IP решаются через `proxy_protocol`

> ℹ️ **Если нужна максимальная легитимность без лишней сложности:** Вариант D (Self-SNI) — оптимальный выбор. Один скрипт разворачивает полноценный стек: сертификат, Xray, Nginx с реальным сайтом, CLI-инструменты. Сервер выглядит как обычный веб-хостинг. Добавление CDN-протоколов потребует перехода на Вариант B или C.

> ℹ️ **Если панель не планируется:** Вариант A (Xray напрямую на 443 с XHTTP+Reality) проще в обслуживании, нет зависимостей. Subscription endpoint отдаётся Nginx на отдельном порту. Добавление CDN-протоколов потребует перехода на Вариант B или C.

---

## 11. Открытые вопросы для инженерной команды

| # | Вопрос | Варианты / Комментарий |
|---|---|---|
| 1 | Reality vs TLS+fallbacks | Если нужны 10+ протоколов или панель → Вариант C. Если приоритет скрытность + простота → Вариант A или B с Reality. |
| 2 | HAProxy vs Nginx stream | HAProxy решает проблему реальных IP чище (`send-proxy`). Nginx stream + `proxy_protocol` сложнее, но один демон меньше. Выбор зависит от операционных предпочтений команды. |
| 3 | Панель управления | Marzban (Python) vs 3x-ui (Go). Оба поддерживают Reality и sub-links. Marzban активнее развивается; 3x-ui — fork оригинального x-ui с большим сообществом. |
| 4 | CDN или прямой IP | CDN (Cloudflare) защищает от IP-блокировок, но является MitM. Прямой IP + Reality — максимальная конфиденциальность. Возможна гибридная схема: Reality для прямых клиентов, WS/CDN как fallback. |
| 5 | Выбор decoy-домена для Reality | Требование: поддержка TLSv1.3 + HTTP/2. Проверка: `xray tls ping <домен>`. Примеры: `www.microsoft.com`, `www.apple.com`, `dl.google.com`. |
| 6 | Порт Nginx при Варианте B | 7443 в примерах — произвольный выбор. Меняется в двух местах: `stream upstream` + `listen` в server block. Никаких ограничений нет. |
| 7 | Автоматизация | Xray-examples содержит `generate.sh` для All-in-One. Для Nginx stream автоматизации нет — рассмотреть Ansible/Terraform для воспроизводимых деплоев. Вариант D поставляется с готовым bash-скриптом. |
| 8 | Reality vs Self-SNI (Вариант D) | Self-SNI устойчивее к active probing: IP сервера, домен, сертификат и сайт полностью согласованы — нет расхождения с 3rd-party decoy. Reality не требует домена и проще в деплое. Гибридный вариант: Reality для клиентов без домена + Self-SNI там, где domain ownership критичен для легитимности сервера. |
| 9 | Вариант D vs Вариант C | Оба — VLESS+TLS+fallbacks. Разница в масштабе и цели: C оптимизирован под максимум протоколов (unix sockets, xver, gRPC через h2c), D — под максимальную простоту и достоверность легенды (один fallback, TCP-порт, bash-автоматизация). При необходимости расширить Вариант D до C — требуется только добавление fallback-цепочки и unix-сокетов в существующий конфиг. |

---

*Документ сгенерирован на основе технического диалога. Источники: Xray-examples (github.com/XTLS/Xray-examples), XTLS/REALITY, ServerTechnologies/xray-with-selfsni, сравнительный анализ Nginx stream / HAProxy / native fallbacks / Self-SNI.*

---

## 12. Примеры lxhao61 (integrated-examples): расширенные паттерны

Репозиторий lxhao61/integrated-examples содержит production-ориентированные конфигурации с полной поддержкой PROXY protocol, JSONC-форматом, IPv6 и HTTP/3. Ниже — разбор пяти выбранных разделов.

---

### 12.1 Xray(M+H+K+A)+Nginx — REALITY с таргетом на собственный Nginx + XHTTP + mKCP

**Ключевая идея:** Xray стоит на порту 443 с VLESS+Vision+REALITY, но `realitySettings.target` указывает не на сторонний сайт (microsoft.com), а на **собственный Nginx на порту 8443**. Это объединяет преимущества Reality (нет своего сертификата, максимальная скрытность) и Self-SNI (декой — реальный сайт на том же IP). При active probing цензор получает валидный сертификат вашего домена с вашего IP.

```
Internet :443 (TCP)
    │
    ▼
Xray VLESS+Vision+REALITY (port 443)
  realitySettings.target = 127.0.0.1:8443  ← собственный Nginx!
  xver: 1  ← PROXY protocol → Nginx получает реальный IP
    │
    ├── Клиент «свой» (REALITY handshake)  → прокси (M)
    └── Fallback → :2023 (VLESS+XHTTP plain)
                     │
                     └── Nginx :cdn_domain (grpc_pass → :2023)  (H)
                              └── REALITY套娃: клиент с Reality → XHTTP → Nginx (K)

Nginx :8443  — HTTPS сайт (декой для REALITY) + XHTTP reverse proxy
Nginx QUIC :443  — HTTP/3 server (отдельный listener)
VLESS+mKCP  :2052  — отдельный порт, UDP (A)
```

**Протоколы:**

| Буква | Протокол | Примечание |
|---|---|---|
| M | VLESS+Vision+REALITY | Основной. Xray на 443, target = собственный Nginx |
| H | VLESS+XHTTP+TLS | Nginx терминирует TLS, grpc_pass → Xray :2023 (CDN-совместимо) |
| K | VLESS+XHTTP+REALITY (套娃) | Клиент подключается как M (REALITY), внутри XHTTP. Конфиг общий с H |
| A | VLESS+mKCP+seed | UDP, отдельный порт 2052, нет CDN |

**Ключевые особенности конфига:**

```jsonc
// Xray: главный inbound
{
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "UUID", "flow": "xtls-rprx-vision" }],
    "decryption": "none",
    "fallbacks": [{ "dest": 2023 }]  // → VLESS+XHTTP inbound
  },
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "target": 8443,          // ← СОБСТВЕННЫЙ Nginx, не microsoft.com
      "xver": 1,               // PROXY protocol → Nginx видит реальный IP
      "serverNames": ["h3a.example.com"],
      "privateKey": "...",
      "shortIds": [""]
    }
  }
}
```

```nginx
# Nginx: принимает соединения от REALITY target + отдаёт XHTTP
server {
    listen 127.0.0.1:8443 ssl proxy_protocol;  # принимает PROXY protocol от Xray
    http2 on;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    server_name h3a.example.com;

    location /VLSpdG9k {
        grpc_pass grpc://127.0.0.1:2023;  # VLESS+XHTTP inbound
    }
    location / { root /var/www/html; }  # decoy сайт
}

# HTTP/3 — отдельный listener на 443 UDP (не конфликтует с Xray на TCP 443)
server {
    listen 443 quic reuseport;
    server_name h3a.example.com;
    add_header Alt-Svc 'h3=":443"; ma=86400';
    # ... XHTTP + сайт
}
```

> ⚠️ **Два варианта подключения:** `1_*` — Local Loopback (127.0.0.1), `2_*` — Unix Domain Sockets (`/dev/shm/*.sock`). UDS-вариант убирает накладные расходы TCP-стека.

> ℹ️ **HTTP/3 и TCP:443 не конфликтуют:** QUIC работает по UDP. Xray занимает TCP:443, Nginx занимает UDP:443 (QUIC) независимо.

| ✅ Плюсы | ❌ Минусы |
|---|---|
| Reality без зависимости от стороннего сайта — декой на своём IP | Сложная цепочка: Xray→Nginx→Xray (XHTTP套娃) |
| PROXY protocol сквозь всю цепочку — реальные IP везде | Требует Nginx ≥ v1.25.1 для H2C+HTTP/1.1 на одном порту |
| H/K — CDN-совместимые протоколы на том же 443 | JSONC-формат конфига (только Xray, не V2Ray) |
| HTTP/3 через Nginx QUIC без конфликтов | mKCP не проходит через CDN |

---

### 12.2 Xray(E+F+H+A)+Nginx — Nginx stream SNI с VLESS+Vision+TLS, Trojan и XHTTP

**Ключевая идея:** Nginx stream делает SNI-роутинг и **немедленно включает PROXY protocol** для всех upstream. Xray inbounds (E и F) сами терминируют TLS и принимают `proxy_protocol` через `rawSettings.acceptProxyProtocol`. Каждый протокол работает на отдельном домене и использует отдельный TLS-сертификат.

```
Internet :443 (TCP)
    │
    ▼
Nginx stream (SNI routing + proxy_protocol ON для всех)
    ├── h2t.example.com → :5443  Xray VLESS+Vision+TLS (E)
    │                               fallback → Nginx :88 (decoy)
    ├── t2n.example.com → :6443  Xray Trojan+RAW+TLS (F)
    │                               fallback → Nginx :88 (decoy)
    ├── cdn.example.com → :7443  Nginx HTTPS/H2 (CDN proxy for H)
    │                               grpc_pass → Xray :2023 (VLESS+XHTTP)
    └── h3a.example.com → :8443  Nginx HTTPS/H2+H3 (for H)
                                    grpc_pass → Xray :2023 (VLESS+XHTTP)

Nginx QUIC :443 (UDP) — HTTP/3 (независимо от stream TCP:443)
VLESS+mKCP  :2052 — UDP, отдельный порт (A)
```

**Протоколы:**

| Буква | Протокол | Домен | Особенность |
|---|---|---|---|
| E | VLESS+Vision+TLS | h2t.example.com | Xray терминирует TLS, fallback → Nginx HTTP |
| F | Trojan+RAW+TLS | t2n.example.com | Только CHACHA20-POLY1305, TLS 1.2 max, fallback → Nginx HTTP |
| H | VLESS+XHTTP+TLS | cdn.example.com / h3a.example.com | Nginx терминирует TLS, CDN-совместимо |
| A | VLESS+mKCP+seed | — | UDP :2052 |

**Реальные IP — полная цепочка:**

```
Client → Nginx stream (proxy_protocol ON) → Xray inbound (acceptProxyProtocol: true)
Client → Nginx stream (proxy_protocol ON) → Nginx HTTP (real_ip_header proxy_protocol)
```

```nginx
# Nginx stream
stream {
    map $ssl_preread_server_name $tcpsni_name {
        h2t.example.com vlesst;
        t2n.example.com trojan;
        cdn.example.com  cdnh2;
        h3a.example.com  http3;
    }
    server {
        listen 443;
        ssl_preread on;
        proxy_protocol on;    # ← включён глобально для stream server
        proxy_pass $tcpsni_name;
    }
}
```

```jsonc
// Xray: VLESS+Vision+TLS (E) — принимает proxy_protocol
{
  "listen": "127.0.0.1",
  "port": 5443,
  "protocol": "vless",
  "settings": {
    "clients": [{ "id": "UUID", "flow": "xtls-rprx-vision" }],
    "decryption": "none",
    "fallbacks": [{ "dest": 88, "xver": 1 }]  // к Nginx HTTP, шлёт xver обратно
  },
  "streamSettings": {
    "network": "raw",
    "security": "tls",
    "tlsSettings": { "certificates": [{ "certificateFile": "...", "keyFile": "..." }] },
    "rawSettings": { "acceptProxyProtocol": true }  // принимает от Nginx stream
  }
}

// Xray: Trojan+RAW+TLS (F) — намеренно TLS 1.2 + non-AES cipher
{
  "listen": "127.0.0.1",
  "port": 6443,
  "protocol": "trojan",
  "settings": {
    "clients": [{ "password": "diy6443" }],
    "fallbacks": [{ "dest": 88, "xver": 1 }]
  },
  "streamSettings": {
    "network": "raw",
    "security": "tls",
    "tlsSettings": {
      "minVersion": "1.2", "maxVersion": "1.2",
      "cipherSuites": "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256:TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
    },
    "rawSettings": { "acceptProxyProtocol": true }
  }
}
```

> ⚠️ **Trojan без Vision:** Оригинальные Trojan и Trojan-Go клиенты не поддерживают TLS fingerprint spoofing — lxhao61 не рекомендует их использовать. Xray-клиент с Trojan-протоколом работает корректно.

> ℹ️ **Non-AES для Trojan:** Выбор CHACHA20-POLY1305 + TLS 1.2 max делает трафик Trojan+F визуально непохожим на трафик E (VLESS+Vision, AES, TLS 1.3). Два протокола с разными fingerprint на разных доменах.

| ✅ Плюсы | ❌ Минусы |
|---|---|
| Два независимых TLS-протокола (VLESS+Vision, Trojan) на разных доменах | Требует несколько TLS-сертификатов (по домену) |
| PROXY protocol сквозной — Nginx stream → Xray → Nginx HTTP | Nginx stream module обязателен |
| CDN-маршрут (cdn.example.com) и прямой (h2t, t2n) на одном 443 | Сложность отладки: 4 upstream в stream |
| Trojan как дополнительный протокол без Reality | Trojan без оригинального клиента |
| HTTP/3 через Nginx QUIC на 443 UDP | — |

---

### 12.3 V2Ray(Other Configuration) — операционные рецепты

Набор патчей, применяемых к любому базовому конфигу V2Ray или Xray.

#### Мульти-пользователи (multi.json)

**VMess / VLESS / Trojan** — добавить объекты в `clients[]`:
```jsonc
"clients": [
  { "id": "UUID-1", "email": "user1@example.com" },
  { "id": "UUID-2", "email": "user2@example.com" }
]
```

**Shadowsocks 2022** — отдельная схема с master key + per-user sub-keys:
```jsonc
"settings": {
  "method": "2022-blake3-aes-128-gcm",
  "password": "MASTER-KEY==",      // master key
  "clients": [
    { "password": "SUB-KEY-1==", "email": "user1@example.com" },
    { "password": "SUB-KEY-2==", "email": "user2@example.com" }
  ]
}
// Клиент использует: "MASTER-KEY==:SUB-KEY-1=="
```

> ⚠️ `2022-blake3-chacha20-poly1305` не поддерживает multi-user. V2Ray не поддерживает SS 2022 вообще.

#### Встроенный DNS (dns.json)

Решает проблемы с системным DNS и ограничениями исходящих портов:
```jsonc
// Добавить перед inbounds:
"dns": {
  "servers": [
    "https+local://dns.google/dns-query",
    "https+local://dns.adguard.com/dns-query"
  ]
},
// Freedom outbound изменить:
{ "protocol": "freedom", "settings": { "domainStrategy": "UseIP" } }
```

#### Блокировка CN-трафика (cn.json)

Блокирует обратный доступ к китайским ресурсам (актуально для серверов внутри или на выходе из РФ):
```jsonc
"routing": {
  "domainStrategy": "IPIfNonMatch",
  "rules": [
    { "type": "field", "domain": ["geosite:google", "geosite:geolocation-!cn"], "outboundTag": "direct" },
    { "type": "field", "domain": ["geosite:cn"],  "outboundTag": "block" },
    { "type": "field", "ip":     ["geoip:cn"],    "outboundTag": "block" },
    { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" }
  ]
}
```

#### Удаление блокировки BT (bt.json)

Три шага для полного отключения BT-блокировки:
1. В каждом inbound удалить блок `sniffing` (отключает traffic detection для этого inbound)
2. В `routing.rules` удалить правило `bittorrent → block`
3. В `outbounds` удалить blackhole тег `block` (если он не нужен другим правилам)

#### Статистика трафика (traffic.json)

Включает per-user статистику через `StatsService` API на `:10085`:

```jsonc
// Глобальные параметры (добавить на верхний уровень):
"stats": {},
"api": { "tag": "api", "services": ["StatsService"] },
"policy": {
  "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
  "system": { "statsInboundUplink": false, "statsInboundDownlink": false }
},

// В inbounds добавить API-listener:
{ "listen": "127.0.0.1", "port": 10085, "protocol": "dokodemo-door",
  "settings": { "address": "127.0.0.1" }, "tag": "api" },

// В routing.rules (первым правилом):
{ "type": "field", "inboundTag": ["api"], "outboundTag": "api" },

// Каждый клиент должен иметь уникальный email:
{ "id": "UUID", "level": 0, "email": "user@example.com" }
```

Просмотр статистики: bash-скрипт `xray.sh` из репозитория, запускается от root. После перезапуска Xray счётчики сбрасываются.

> ⚠️ Статистика потребляет ресурсы сервера. Не включать без необходимости.

#### SNI-роутинг средствами V2Ray/Xray (1_sni.json, 2_sni.json)

Исторически применялся когда Nginx stream недоступен. Сейчас считается устаревшим — вытеснен Nginx stream. Два варианта:

**1_sni.json — Local Loopback:** `dokodemo-door` на 443 + TLS sniffing → routing → freedom redirect на внутренние порты.

**2_sni.json — Unix Domain Sockets:** То же, но forward через `domainsocket` вместо TCP. Оба не поддерживают PROXY protocol (реальный IP теряется).

---

### 12.4 Service Configuration — systemd-юниты

Production-ready unit files. Ключевые параметры xray.service:

```ini
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray/xray run --config /usr/local/etc/xray/xray.jsonc
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000    # критично для высоконагруженных серверов
```

> ℹ️ Xray поддерживает JSONC (JSON с комментариями) напрямую — файл можно называть `.jsonc`, комментарии `//` сохраняются.

Nginx.service добавляет `ExecStartPre=-t` (проверка конфига перед запуском) и `ExecReload` (graceful reload без прерывания соединений). Nginx поддерживает `systemctl reload` — в отличие от Xray, у которого `reload` не работает (нет `ExecReload` в официальном unit).

---

### 12.5 Client Configuration — клиентские конфиги

Репозиторий содержит готовые JSON-конфиги для оригинальных клиентов (v2ray-core, xray-core). Полный список поддерживаемых протоколов:

**V2Ray-совместимые (файлы `v2ray_*.json`):**

| Файл | Протокол |
|---|---|
| `v2ray_vmess_ws_tls_config.json` | VMess + WebSocket + TLS |
| `v2ray_vmess_kcp_config.json` | VMess + mKCP |
| `v2ray_vmess_grpc_tls_config.json` | VMess + gRPC + TLS |
| `v2ray_vless_ws_tls_config.json` | VLESS + WebSocket + TLS |
| `v2ray_vless_http_tls_config.json` | VLESS + HTTP/2 + TLS |
| `v2ray_vless_kcp_config.json` | VLESS + mKCP |
| `v2ray_vless_grpc_tls_config.json` | VLESS + gRPC + TLS |
| `v2ray_trojan_ws_tls_config.json` | Trojan + WebSocket + TLS |
| `v2ray_trojan_http_tls_config.json` | Trojan + HTTP/2 + TLS |
| `v2ray_SS_grpc_tls_config.json` | Shadowsocks + gRPC + TLS |
| `SS_v2ray-plugin_tls.json` | Shadowsocks + v2ray-plugin (WS+TLS) |

**Xray-exclusive (файлы `xray_*.jsonc`):**

| Файл | Протокол |
|---|---|
| `xray_vless_vision_reality_config.jsonc` | VLESS + Vision + REALITY |
| `xray_vless_vision_tls_config.jsonc` | VLESS + Vision + TLS |
| `xray_vless_xhttp_reality_config.jsonc` | VLESS + XHTTP + REALITY |
| `xray_vless_xhttp_reality-tls_config.jsonc` | VLESS + XHTTP + REALITY (套娃 через TLS) |
| `xray_vless_xhttp_tls_config.jsonc` | VLESS + XHTTP + TLS (несколько режимов) |
| `xray_vless_httpupgrade_tls_config.jsonc` | VLESS + HTTPUpgrade + TLS |
| `xray_trojan_raw_tls_config.jsonc` | Trojan + RAW + TLS |
| `xray_vmess_xhttp_tls_config.jsonc` | VMess + XHTTP + TLS |
| `xray_vmess_httpupgrade_tls_config.jsonc` | VMess + HTTPUpgrade + TLS |

> ℹ️ Клиентские конфиги используют имя файла только для навигации — при использовании переименовать в `config.json`. Для Desktop: рекомендуется SwitchyOmega для браузера поверх SOCKS/HTTP прокси от клиента.

---

### 12.6 Сравнение паттернов lxhao61 с основными вариантами

| Аспект | M+H+K+A+Nginx | E+F+H+A+Nginx | Вариант B (из §3) |
|---|---|---|---|
| Кто занимает :443 | Xray (REALITY) | Nginx stream | Nginx stream |
| Reality | ✅ Target = собственный Nginx | ❌ | ✅ Target = 3rd party |
| TLS-сертификат | ✅ На Nginx (для decoy) | ✅ На каждом Xray inbound | ✅ На Nginx HTTPS server |
| CDN-протоколы | ✅ XHTTP через Nginx | ✅ XHTTP через Nginx | ✅ WS/gRPC через Nginx |
| Trojan | ❌ | ✅ Отдельный домен+сертификат | ❌ |
| PROXY protocol | ✅ xver в realitySettings | ✅ proxy_protocol в stream | ⚠️ Требует настройки |
| HTTP/3 | ✅ Nginx QUIC :443 UDP | ✅ Nginx QUIC :443 UDP | ❌ (не в базовом примере) |
| mKCP | ✅ Отдельный UDP-порт | ✅ Отдельный UDP-порт | ❌ |
| UDS-вариант | ✅ 2_* конфиги | ✅ 2_* конфиги | ❌ |
| Сложность | Высокая | Высокая | Средняя |

*Источники: lxhao61/integrated-examples (github.com/lxhao61/integrated-examples)*
