# Xray VPN — Инженерная документация

Практическое руководство по развёртыванию Xray на порту 443. Документация охватывает все архитектурные паттерны, от минимального до production-ready, с готовыми конфигами, пошаговыми инструкциями и операционными процедурами.

> Основано на [lxhao61/integrated-examples](https://github.com/lxhao61/integrated-examples) и [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples).

---

## Структура репозитория

```
.
├── docs/
│   ├── 00-prerequisites.md        # Требования, установка Xray и Nginx
│   ├── 01-architecture.md         # Сравнение архитектур и протоколов
│   ├── 02-tls-certificates.md     # Управление TLS-сертификатами (acme.sh)
│   ├── 03-firewall-dns.md         # Firewall, DNS-записи, IPv6
│   ├── 04-subscription-links.md   # Subscription links и клиентские конфиги
│   ├── 05-management-panels.md    # Marzban, 3x-ui — установка и интеграция
│   ├── 06-troubleshooting.md      # Диагностика и типичные ошибки
│   └── 07-operations.md           # Ротация ключей, бэкап, мониторинг
├── configs/
│   ├── variant-a/                 # Xray напрямую на 443 (Reality/XHTTP)
│   ├── variant-b/                 # Nginx stream SNI routing
│   ├── variant-c/                 # Xray native fallbacks (All-in-One)
│   ├── variant-d/                 # Self-SNI (VLESS+Vision+TLS)
│   ├── lxhao61-M+H+K+A/          # Production: Reality + XHTTP + mKCP
│   ├── lxhao61-E+F+H+A/          # Production: VLESS+Vision+TLS + Trojan + XHTTP
│   ├── systemd/                   # systemd unit-файлы
│   ├── client/                    # Клиентские конфиги (v2ray-core, xray-core)
│   └── other/                     # DNS, BT, CN-блокировка, статистика
└── scripts/
    ├── gen-keys.sh                # Генерация UUID, Reality-ключей, Short ID
    └── check-config.sh            # Валидация конфигов перед деплоем
```

---

## Быстрый старт

### Выбор архитектуры

| Ситуация | Вариант |
|---|---|
| Нужна только Reality, минимум сложности | [Вариант A](configs/variant-a/) |
| Reality + CDN-протоколы на одном 443 | [Вариант B](configs/variant-b/) |
| Максимум протоколов, нет Reality | [Вариант C](configs/variant-c/) |
| Максимальная легитимность, собственный сайт | [Вариант D](configs/variant-d/) |
| Production с Trojan, HTTP/3, PROXY protocol | [lxhao61 M+H+K+A](configs/lxhao61-M+H+K+A/) |

### Минимальный деплой (Вариант A)

```bash
# 1. Установить Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# 2. Сгенерировать ключи
/usr/local/bin/xray x25519          # → privateKey + publicKey
/usr/local/bin/xray uuid            # → UUID клиента
openssl rand -hex 8                  # → shortId

# 3. Скопировать конфиг
cp configs/variant-a/xray.jsonc /usr/local/etc/xray/config.json
# Заменить UUID, privateKey, shortIds в конфиге

# 4. Запустить
systemctl enable --now xray
```

Подробнее: [docs/00-prerequisites.md](docs/00-prerequisites.md)

---

## Кодировка букв протоколов (lxhao61)

| Буква | Протокол |
|---|---|
| M | VLESS + Vision + REALITY |
| E | VLESS + Vision + TLS |
| F | Trojan + RAW + TLS |
| H | VLESS + XHTTP + TLS |
| K | VLESS + XHTTP + REALITY (套娃) |
| A | VLESS + mKCP + seed |
| N | NaiveProxy (Caddy) |
| T | Trojan-Go (Caddy) |

---

## Версионные требования

| Функция | Минимальная версия |
|---|---|
| REALITY | Xray ≥ v1.8.0 |
| XHTTP (полный, разделение up/down) | Xray ≥ v24.11.30 |
| XHTTP + REALITY | Xray ≥ v24.10.31 |
| HTTP/3 server | Nginx ≥ v1.25.0 + SSL lib с QUIC |
| H2C + HTTP/1.1 на одном порту | Nginx ≥ v1.25.1 |
| `ssl_reject_handshake` | Nginx ≥ v1.19.4 |

---

## Ссылки

- [Xray-core releases](https://github.com/XTLS/Xray-core/releases)
- [Xray документация](https://xtls.github.io/)
- [lxhao61/integrated-examples](https://github.com/lxhao61/integrated-examples)
- [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples)
- [acme.sh](https://github.com/acmesh-official/acme.sh)
