# lxhao61 M+H+K+A + Nginx — Production конфиг

Источник: [lxhao61/integrated-examples — Xray(M+H+K+A)+Nginx](https://github.com/lxhao61/integrated-examples/tree/main/Xray(M%2BH%2BK%2BA)%2BNginx)

## Что включено

| Буква | Протокол | Транспорт | Описание |
|---|---|---|---|
| M | VLESS + Vision | REALITY | Основной. Xray на :443, target = собственный Nginx на :8443 |
| H | VLESS + XHTTP | TLS | CDN-совместимый. Nginx терминирует TLS, grpc_pass → Xray :2023 |
| K | VLESS + XHTTP | REALITY (套娃) | Клиент подключается через Reality (M), внутри — XHTTP. Конфиг общий с H |
| A | VLESS + mKCP | seed | UDP :2052. Высокая пропускная способность при потерях. Без CDN |

## Файлы

- `xray.jsonc` — конфиг Xray (Local Loopback, вариант 1)
- `nginx.conf` — полный конфиг Nginx (HTTP/2 + HTTP/3)
- `README-upstream.md` — оригинальный README от lxhao61 (на китайском)

## Требования

- Xray **≥ v24.11.30** (для полного XHTTP с разделением up/down)
- Nginx **≥ v1.25.1** (для H2C + HTTP/1.1 на одном порту)
- Nginx **≥ v1.25.0** + SSL lib с QUIC (для HTTP/3, опционально)
- Два домена с A-записями на этот сервер: `cdn.example.com` и `h3a.example.com`
- TLS-сертификаты для обоих доменов

## Что заменить в xray.jsonc

| Placeholder | Что поставить | Команда |
|---|---|---|
| `edfd12f5-acc9-...` | UUID клиента M | `xray uuid` |
| `af7d5cf8-442d-...` | UUID клиента H/K | `xray uuid` |
| `0a652466-dd56-...` | UUID клиента A | `xray uuid` |
| `iD0BftokWqJ6...` | Reality privateKey | `xray x25519` → Private key |
| `h3a.example.com` | Ваш домен для Reality | — |
| `/VLSpdG9k` | Случайный path для XHTTP | `openssl rand -hex 8` |
| `60VoqhfjP79nBQyU` | mKCP seed | любая случайная строка |

## Что заменить в nginx.conf

| Placeholder | Что поставить |
|---|---|
| `cdn.example.com` | Домен для CDN/XHTTP клиентов |
| `h3a.example.com` | Домен для Reality target + HTTP/3 |
| `/home/tls/cdn.example.com/...` | Путь к сертификату |
| `/home/tls/h3a.example.com/...` | Путь к сертификату |
| `/var/www/html` | Путь к decoy-сайту |
| `/VLSpdG9k` | Должен совпадать с path в xray.jsonc |

## Ключевая особенность: Reality target = собственный Nginx

В отличие от стандартного Reality (target = microsoft.com), здесь:

```jsonc
"realitySettings": {
  "target": 8443,              // ← собственный Nginx!
  "xver": 1,                   // PROXY protocol → Nginx видит реальный IP
  "serverNames": ["h3a.example.com"]
}
```

Active probing цензора получает валидный TLS-сертификат `h3a.example.com` с этого же IP — нет расхождения с 3rd-party decoy.

## Subscription Links

После замены placeholder-значений сформируйте ссылки:

**M (VLESS+Vision+REALITY):**
```
vless://UUID_M@SERVER_IP:443?security=reality&encryption=none&pbk=PUBLIC_KEY&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=h3a.example.com&sid=SHORT_ID#M
```

**H (VLESS+XHTTP+TLS через CDN):**
```
vless://UUID_H@cdn.example.com:443?security=tls&encryption=none&type=xhttp&path=/VLSpdG9k&sni=cdn.example.com#H-CDN
```

**K (VLESS+XHTTP+REALITY, 套娃):**
```
vless://UUID_H@SERVER_IP:443?security=reality&encryption=none&pbk=PUBLIC_KEY&fp=chrome&type=xhttp&path=/VLSpdG9k&sni=h3a.example.com&sid=SHORT_ID#K
```
(UUID тот же что H, т.к. K/H шарят один inbound)

**A (VLESS+mKCP):**
```
vless://UUID_A@SERVER_IP:2052?security=none&encryption=none&type=kcp&seed=SEED#A
```
