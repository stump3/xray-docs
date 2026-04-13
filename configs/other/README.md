# configs/other — Операционные патчи

Набор JSON-фрагментов, применяемых к любому базовому конфигу. Источник: [lxhao61 — V2Ray(Other Configuration)](https://github.com/lxhao61/integrated-examples/tree/main/V2Ray(Other%20Configuration)).

## Файлы

### multi.json — Множество пользователей

Добавить объекты в `clients[]` для VMess/VLESS/Trojan:
```jsonc
"clients": [
  { "id": "UUID-1", "email": "user1@example.com" },
  { "id": "UUID-2", "email": "user2@example.com" }
]
```

Для Shadowsocks 2022 — особая схема с master key и sub-keys (см. файл).

> `2022-blake3-chacha20-poly1305` не поддерживает multi-user.

### dns.json — Встроенный DNS

Решает проблемы с системным DNS и ограничениями исходящих портов. Использует DoH (DNS over HTTPS) через Google и AdGuard.

### cn.json — Блокировка китайского трафика

Блокирует обратный доступ к китайским ресурсам — актуально для серверов в/на выходе из РФ. Использует `geosite:cn` и `geoip:cn`.

### bt.json — Разблокировка BitTorrent

Три шага для отключения BT-блокировки:
1. Удалить блок `sniffing` из каждого inbound
2. Удалить правило `bittorrent → block` из routing
3. Удалить outbound с тегом `block` (если не нужен другим правилам)

### traffic.json — Статистика трафика

Включает per-user статистику через `StatsService` API на порту `10085`. Подробности в файле.

Для просмотра статистики:
```bash
chmod +x configs/other/xray.sh
./xray.sh    # запускать от root
```

> Статистика потребляет ресурсы сервера. Включать только при необходимости.

### xray.sh — Скрипт просмотра статистики

Подключается к Xray gRPC API на `127.0.0.1:10085` и выводит трафик по пользователям. Требует предварительной настройки `traffic.json`.
