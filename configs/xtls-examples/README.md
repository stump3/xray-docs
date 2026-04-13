# configs/xtls-examples — Официальные примеры XTLS/Xray-core

Источник: [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples)

Это **официальные** примеры от команды Xray-core. В отличие от lxhao61, здесь акцент на минимализм и ясность, а не на production-hardening. Каждый каталог — самодостаточный пример одного сценария с парой server/client конфигов.

---

## Каталоги

### VLESS-XHTTP-Reality/
**Минимальный современный конфиг** — рекомендован командой XTLS как точка входа.

- Целевая версия: **≥ v25.3.6**
- Xray напрямую на :443, без Nginx
- Использует новое имя поля `target` (вместо устаревшего `dest`)
- `fingerprint: "chrome"` — дефолт с v24.12.18, явно не указывается
- Включает варианты с блокировкой CN-трафика (`server-block-cn.jsonc`, `client-bypass-cn.jsonc`)

> Аналог: Вариант A в нашей классификации, но ещё чище и новее.

### VLESS-Vision-Reality/
Минимальный конфиг **VLESS + Vision + REALITY** (TCP транспорт).

- Использует старое поле `dest` — репозиторий ещё не обновлён на `target`
- `loglevel: "debug"` — явно для разработки/тестирования
- Поддерживает `1.1.1.1:443` как target без serverNames (обход ограничений скорости в Иране)
- Нет блокировки CN-трафика и нет PROXY protocol

### VLESS-Vision-TLS/
**VLESS + XTLS Vision + TLS** (собственный сертификат). Содержит подробный README от rprx о правилах использования Vision: clean IP, запрет смешивания с обычными TLS-прокси, обязательный uTLS fingerprint.

- Fallbacks на порты 8001 (HTTP/1.1) и 8002 (H2) с `xver: 1`
- `rejectUnknownSni: true` в tlsSettings
- По умолчанию блокирует CN-трафик (`geoip:cn → block`)

### All-in-One-fallbacks/
**Максимальный конфиг** — 17 протоколов и транспортов на порту 443 одновременно.

- VLESS+TCP+XTLS как точка входа
- Unix Domain Sockets (`/dev/shm/h1.sock`, `/dev/shm/h2c.sock`) для связи с Nginx
- Встроенная статистика (`StatsService`, `HandlerService`)
- `generate.sh` — скрипт автозамены всех placeholder-значений
- Тестировался с Xray 1.7.2 — часть конфигов может быть устаревшей

> Аналог: Вариант C в нашей классификации.

### VLESS-XHTTP3-Nginx/
**VLESS + XHTTP + HTTP/3 (QUIC)** через Nginx.

- Xray слушает на Unix Domain Socket `/dev/shm/xrxh.socket` (не TCP-порт)
- Nginx: `listen 443 quic` + `grpc_pass unix:/dev/shm/xrxh.socket`
- Режим `stream-one` в `xhttpSettings.mode`
- `xmux` параметры с учётом лимитов Nginx (maxConcurrency: 128, hMaxRequestTimes: 1000)
- Опциональный `downloadSettings` для раздельного H2/H3 down-stream

### VLESS-SplitHTTP-Nginx/
Старый пример SplitHTTP — использует **устаревшее имя** `splithttp`/`splithttpSettings`.

> ⚠️ В текущем Xray (≥ v24.11.30) транспорт называется `xhttp`/`xhttpSettings`. Этот конфиг требует обновления перед использованием.

### VLESS-WSS-Nginx/
Простой **VLESS + WebSocket + TLS** через Nginx. Минимальный конфиг с блокировкой CN.

### VLESS-gRPC-Reality/
**VLESS + gRPC + Reality** — нестандартная конфигурация: Xray слушает на **порту 80**, не 443. Используется Yahoo как target.

### ReverseProxy/
Паттерн **bridge → portal** для случаев, когда сервер не имеет прямого доступа в интернет. Три варианта: VMess-TCP, VLESS-TCP-XTLS-WS, Shadowsocks-2022.

### Serverless-for-Iran/
Конфигурации для работы через **Cloudflare Workers** и другие serverless-платформы. Актуально при блокировке прямых IP.

---

## Версионные требования (по конфигам)

| Конфиг | Мин. версия Xray |
|---|---|
| VLESS-XHTTP-Reality | ≥ v25.3.6 |
| VLESS-XHTTP3-Nginx | ≥ v24.11.30 |
| VLESS-Vision-Reality | ≥ v1.8.0 |
| All-in-One-fallbacks | ≥ v1.7.2 (тестировался) |
| VLESS-SplitHTTP-Nginx | ⚠️ Устарел, нужен рефакторинг |
