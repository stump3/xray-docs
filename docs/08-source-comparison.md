# Сравнение источников конфигурации: XTLS vs lxhao61 vs наши варианты

Три источника конфигов в этом репозитории решают одну задачу, но с разных позиций. Этот документ помогает понять, что брать откуда и почему.

---

## Философия и целевая аудитория

| | XTLS/Xray-examples | lxhao61/integrated-examples | Наши варианты (A–D) |
|---|---|---|---|
| **Цель** | Обучение, reference | Production-hardening | Практический выбор архитектуры |
| **Аудитория** | Разработчики, новички | Опытные операторы | Инженерная команда |
| **Стиль** | Минимальный, один сценарий | Комплексный, best practices | Структурированный, с обоснованием |
| **Актуальность** | Смешанная (старые и новые) | Регулярно обновляется | — |
| **Язык** | EN / ZH | ZH | RU |

---

## Одинаковые паттерны — разная реализация

### VLESS + XHTTP + Reality (самый рекомендуемый паттерн)

| Аспект | XTLS | lxhao61 (M в M+H+K+A) | Наш Вариант A |
|---|---|---|---|
| Целевая версия | ≥ v25.3.6 | ≥ v24.11.30 | ≥ v24.11.30 |
| Поле target/dest | `"target"` (новое) | `"target"` | `"target"` |
| Reality target | Чужой сайт | **Собственный Nginx** | Чужой сайт |
| PROXY protocol | ❌ | ✅ `xver: 1` | ❌ |
| Nginx | ❌ | ✅ Декой + XHTTP reverse proxy | Опционально |
| CN-блокировка | Опционально (`server-block-cn.jsonc`) | ❌ (только BT) | ❌ |
| loglevel | info | warning | warning |
| Сложность | Минимальная | Средняя | Минимальная |

**Вывод:** XTLS даёт чистый старт, lxhao61 добавляет production-слой (PROXY protocol, собственный декой). Для деплоя в серьёзной среде — lxhao61.

---

### VLESS + Vision + Reality

| Аспект | XTLS | lxhao61 (M, без fallback) |
|---|---|---|
| Поле target/dest | `"dest"` ← **устарело** | `"target"` |
| loglevel | `"debug"` ← для тестов | `"warning"` |
| Fallbacks | ❌ | ✅ → XHTTP inbound |
| PROXY protocol | ❌ | ✅ |
| CN-блокировка | ❌ | ❌ (только BT) |
| Особенность | Поддержка `1.1.1.1:443` как target (Иран) | target = собственный Nginx |

**Вывод:** Конфиг XTLS для Vision+Reality устарел в полях (`dest` вместо `target`, `debug` loglevel). lxhao61 — актуальнее и production-ready.

---

### VLESS + Vision + TLS (Вариант D / буква E)

| Аспект | XTLS | lxhao61 (E в E+F+H+A) | Наш Вариант D |
|---|---|---|---|
| Архитектура | VLESS+TLS, fallback → Nginx порты 8001/8002 | Nginx stream → Xray :5443, fallback → Nginx :88 | VLESS+TLS, fallback → Nginx :8080 |
| PROXY protocol | ✅ `xver: 1` | ✅ stream + acceptProxyProtocol | ❌ (нативный IP) |
| `rejectUnknownSni` | ✅ | ❌ | ❌ |
| CN-блокировка | ✅ по умолчанию | ❌ | ❌ |
| Cipher suites | Дефолт Xray | AES + CHACHA20 явно | Дефолт Xray |
| Nginx размещение | Порты 8001/8002 (TCP) | Порт 88 + 7443/8443 | Порт 8080 |
| Trojan рядом | ❌ | ✅ (F — отдельный домен) | ❌ |

---

### All-in-One (максимум протоколов на 443)

| Аспект | XTLS All-in-One | lxhao61 E+F+H+A | Наш Вариант C |
|---|---|---|---|
| Протоколов одновременно | 17 (VLESS/VMess/Trojan/SS × TCP/WS/gRPC/H2) | 4 (E+F+H+A) | Десятки (теоретически) |
| Reality | ❌ | ❌ (E — TLS) | ❌ |
| UDS для Nginx | ✅ `/dev/shm/*.sock` | ✅ (вариант 2_*) | ✅ |
| PROXY protocol | ✅ xver в fallbacks | ✅ везде | ✅ |
| generate.sh | ✅ | ❌ | — |
| Статистика трафика | ✅ встроена | ❌ (отдельный файл) | — |
| HTTP/3 | ❌ | ✅ | — |
| Shadowsocks | ✅ | ❌ | — |
| Целевая версия | ≥ v1.7.2 | ≥ v24.11.30 | — |

---

## Уникальное в XTLS, чего нет в lxhao61

### VLESS-XHTTP3-Nginx — HTTP/3 через UDS
Единственный конфиг, где Xray слушает на **Unix Domain Socket** (`/dev/shm/xrxh.socket`) напрямую, а Nginx делает `grpc_pass unix:...`. Это убирает даже TCP loopback overhead.

```
Client → Nginx :443 QUIC → grpc_pass unix:/dev/shm/xrxh.socket → Xray XHTTP
```

В lxhao61 Xray слушает на TCP (127.0.0.1:2023), UDS используется только для связи Xray→Nginx (variant 2_*), но не Nginx→Xray.

Конфиг также документирует `xmux` параметры с явными лимитами Nginx:
- `maxConcurrency: 128` — HTTP/3 stream limit Nginx
- `hMaxRequestTimes: 1000` — keepalive_requests limit
- `hMaxReusableSecs: 3600` — keepalive_time limit

### ReverseProxy (bridge → portal)
Паттерн для серверов **без прямого входящего интернет-соединения**. Bridge (промежуточный) подключается к portal (выходному), создаётся туннель в обратную сторону.

```
Клиент → Portal (публичный IP) ← Bridge (сервер без внешнего IP)
```

Сценарии: корпоративная сеть, NAT без проброса портов, двойной VPN.

### Serverless-for-Iran
Конфиги для работы через Cloudflare Workers. Весь трафик идёт через CDN-edge без прямого подключения к серверу. Актуально при блокировке всех IP диапазонов провайдера.

### VLESS-gRPC-Reality на порту 80
Нестандартный выбор — Xray слушает на **порту 80** (HTTP), а не 443. Обходит ситуации когда 443 заблокирован, но 80 открыт. Использует Reality поверх gRPC.

### All-in-One generate.sh
Скрипт автоматической замены placeholder-значений (`sed -i`) с генерацией subscription links и QR-кодов. У lxhao61 аналога нет.

---

## Уникальное в lxhao61, чего нет в XTLS

### Reality target = собственный Nginx (паттерн M+H+K+A)
XTLS всегда использует чужой сайт как Reality target (microsoft.com и т.д.). lxhao61 реализует гибридный подход: target — собственный Nginx с реальным сертификатом на том же IP.

```jsonc
// lxhao61 M:
"target": 8443,  // ← собственный Nginx!
"xver": 1        // PROXY protocol → Nginx видит реальный IP
```

Active probing получает сертификат вашего домена с вашего IP — нет расхождения.

### Trojan как отдельный протокол с non-AES fingerprint (буква F)
lxhao61 намеренно ставит Trojan+TLS 1.2+CHACHA20 рядом с VLESS+TLS 1.3+AES:

```jsonc
"maxVersion": "1.2",
"cipherSuites": "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256:..."
```

Два протокола с разными TLS fingerprint на разных доменах — усложняет корреляцию трафика.

### PROXY protocol повсеместно
lxhao61 добавляет `xver: 1` в каждый fallback и `proxy_protocol on` в каждый Nginx stream upstream. В XTLS PROXY protocol встречается только в отдельных примерах (VLESS-Vision-TLS) и не является стандартом.

### HTTP/3 (QUIC) + PROXY protocol на одном сервере
lxhao61 реализует совместное использование TCP:443 (Xray/Nginx stream) и UDP:443 (Nginx QUIC) без конфликтов, с PROXY protocol в обоих случаях.

---

## Критические различия и подводные камни

### 1. Устаревшее поле `dest` vs актуальное `target`

| Конфиг | Поле | Статус |
|---|---|---|
| XTLS VLESS-Vision-Reality | `"dest"` | ⚠️ Устарело (v24.10.31) |
| XTLS VLESS-XHTTP-Reality | `"target"` | ✅ Актуально |
| lxhao61 все конфиги | `"target"` | ✅ Актуально |
| Наш Вариант A | `"target"` | ✅ Актуально |

### 2. Устаревший транспорт `splithttp` vs `xhttp`

В `XTLS/VLESS-SplitHTTP-Nginx` используется `"network": "splithttp"` и `"splithttpSettings"` — **это устаревшее имя**. Начиная с v24.11.30 правильное имя — `"xhttp"` / `"xhttpSettings"`.

```jsonc
// XTLS (устарело):
"network": "splithttp",
"splithttpSettings": { "path": "/split" }

// lxhao61 и наши конфиги (актуально):
"network": "xhttp",
"xhttpSettings": { "path": "/VLSpdG9k" }
```

### 3. loglevel в XTLS-примерах

XTLS VLESS-Vision-Reality: `"loglevel": "debug"` — генерирует огромные логи, не для production.  
Все lxhao61 конфиги: `"loglevel": "warning"` — норма для production.

### 4. `routeOnly: true` в sniffing (только XTLS)

XTLS Vision+Reality использует `"routeOnly": true` в sniffing — trафик используется только для маршрутизации, но не для перезаписи destination. lxhao61 и наши конфиги не используют этот флаг.

```jsonc
// XTLS:
"sniffing": {
  "enabled": true,
  "destOverride": ["http", "tls", "quic"],
  "routeOnly": true   // ← только в XTLS Vision конфигах
}
```

### 5. Reality target с IP-адресом (только XTLS)

XTLS документирует специальный случай: `"dest": "1.1.1.1:443"` с пустым `serverNames`. Это позволяет использовать IP-сертификат Cloudflare и обходить иранские ограничения скорости на SNI-уровне. lxhao61 этого не использует.

---

## Рекомендации по использованию

### Когда использовать XTLS/Xray-examples

- Изучить синтаксис и возможности Xray с нуля
- Взять минимальный рабочий конфиг для быстрого теста (`VLESS-XHTTP-Reality`)
- Настроить ReverseProxy (bridge/portal) — только здесь
- Развернуть Serverless через Cloudflare Workers — только здесь
- Получить полный список fallback-протоколов (All-in-One) как reference

### Когда использовать lxhao61/integrated-examples

- Production-деплой с несколькими протоколами
- Нужен PROXY protocol и реальные IP в логах
- Нужен Trojan как второй протокол с другим TLS fingerprint
- Reality с target на собственный Nginx (гибридный decoy)
- HTTP/3 (QUIC) совместно с другими протоколами

### Когда использовать наши варианты A–D

- Первый деплой с чёткими критериями выбора (см. матрицу в `docs/01-architecture.md`)
- Нужна русскоязычная документация и troubleshooting
- Интеграция с Marzban / 3x-ui
- Нужен документированный процесс: сертификаты, DNS, firewall, ротация ключей

---

## Сводная таблица: протоколы по источникам

| Протокол | XTLS | lxhao61 | Наши варианты |
|---|---|---|---|
| VLESS + XHTTP + Reality | ✅ Minimal | ✅ M (production) | ✅ Вариант A |
| VLESS + Vision + Reality | ✅ (устар. поля) | ✅ M (production) | ✅ Вариант A alt |
| VLESS + Vision + TLS | ✅ | ✅ E | ✅ Вариант D / E |
| Trojan + RAW + TLS | ✅ (в All-in-One) | ✅ F (отдельный домен) | — |
| VLESS + XHTTP + TLS | ✅ SplitHTTP (устар.) | ✅ H | — |
| VLESS + XHTTP3 + H3 | ✅ UDS-вариант | ⚡ В Nginx конфиге | — |
| VLESS + WebSocket + TLS | ✅ | ✅ (в паттернах) | ✅ Вариант B |
| VLESS + gRPC + Reality | ✅ (порт 80) | — | — |
| VLESS + mKCP | ✅ | ✅ A | — |
| VMess + WS/gRPC/H2 | ✅ All-in-One | ✅ (в V2Ray паттернах) | — |
| Shadowsocks + gRPC | ✅ All-in-One | ✅ G | — |
| All-in-One fallbacks | ✅ 17 протоколов | ✅ E+F+H+A (4) | ✅ Вариант C |
| ReverseProxy | ✅ | — | — |
| Serverless/CDN Workers | ✅ | — | — |
