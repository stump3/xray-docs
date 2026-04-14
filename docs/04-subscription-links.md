# 04 — Subscription Links и клиентская конфигурация

## Форматы URI

### VLESS + XHTTP + Reality (Вариант A, K в M+H+K+A)

```
vless://UUID@SERVER_IP:443
  ?security=reality
  &encryption=none
  &pbk=PUBLIC_KEY
  &fp=chrome
  &type=xhttp
  &path=/yourpath
  &sni=www.microsoft.com
  &sid=SHORT_ID
  #имя-профиля
```

### VLESS + Vision + Reality (буква M)

```
vless://UUID@SERVER_IP:443
  ?security=reality
  &encryption=none
  &pbk=PUBLIC_KEY
  &fp=chrome
  &type=tcp
  &flow=xtls-rprx-vision
  &sni=www.microsoft.com
  &sid=SHORT_ID
  #имя-профиля
```

### VLESS + Vision + TLS (Вариант D, буква E)

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

### VLESS + XHTTP + TLS (буква H, CDN-совместимый)

```
vless://UUID@cdn.example.com:443
  ?security=tls
  &encryption=none
  &type=xhttp
  &path=/VLSpdG9k
  &sni=cdn.example.com
  #имя-профиля
```

### Trojan + RAW + TLS (буква F)

```
trojan://PASSWORD@t2n.example.com:443
  ?security=tls
  &type=tcp
  &sni=t2n.example.com
  #имя-профиля
```

### VLESS + mKCP (буква A)

```
vless://UUID@SERVER_IP:2052
  ?security=none
  &encryption=none
  &type=kcp
  &headerType=none
  &seed=SEED_PASSWORD
  #имя-профиля
```

---

## Subscription Endpoint

Текстовый файл с несколькими ссылками (по одной на строку), закодированный в base64. Клиент периодически опрашивает endpoint и обновляет профили.

### Создание subscription файла

```bash
# Создать файл со ссылками
cat > /var/www/sub/config.txt << 'EOF'
vless://UUID1@SERVER_IP:443?security=reality&...#Server-Reality
vless://UUID2@cdn.example.com:443?security=tls&type=xhttp&...#Server-CDN
EOF

# Закодировать в base64
base64 -w 0 /var/www/sub/config.txt > /var/www/sub/encoded

# Ссылка для клиентов:
# https://your-domain.com/sub/encoded
```

### Nginx location для subscription

```nginx
location /sub {
    alias /var/www/sub/;
    default_type text/plain;
    autoindex off;
    # Разрешить только GET
    limit_except GET { deny all; }
}
```

### Автоматическое обновление при добавлении пользователя

```bash
#!/bin/bash
# Регенерация subscription файла
SUB_DIR="/var/www/sub"
CONFIG="$SUB_DIR/config.txt"

# Получить всех пользователей из Xray конфига
python3 - << 'EOF'
import re, json

cfg_raw = open('/usr/local/etc/xray/config.json').read()
cfg_raw = re.sub(r'//.*', '', cfg_raw)
cfg = json.loads(cfg_raw)

SERVER_IP   = "YOUR_SERVER_IP"    # ← заменить
PUBLIC_KEY  = "YOUR_PUBLIC_KEY"   # ← заменить
SHORT_ID    = "YOUR_SHORT_ID"     # ← заменить
PATH        = "/yourpath"         # ← заменить

for inb in cfg['inbounds']:
    if inb.get('protocol') == 'vless':
        for client in inb['settings']['clients']:
            uid   = client['id']
            email = client.get('email', uid[:8])
            # Reality XHTTP link
            link = (f"vless://{uid}@{SERVER_IP}:443"
                    f"?security=reality&encryption=none"
                    f"&pbk={PUBLIC_KEY}&fp=chrome"
                    f"&type=xhttp&path={PATH}"
                    f"&sni=www.microsoft.com&sid={SHORT_ID}"
                    f"#{email}")
            print(link)
EOF

# Перекодировать
base64 -w 0 "$CONFIG" > "$SUB_DIR/encoded"
echo "Subscription updated: https://your-domain.com/sub/encoded"
```

---

## Клиентские конфиги (JSON)

Готовые конфиги в `configs/client/` для использования с оригинальными xray-core / v2ray-core клиентами.

Перед использованием переименовать: `xray_vless_xhttp_reality_config.jsonc` → `config.json`

### Список файлов

**Xray-exclusive (файлы `xray_*.jsonc`):**

| Файл | Протокол |
|---|---|
| `xray_vless_vision_reality_config.jsonc` | VLESS + Vision + REALITY |
| `xray_vless_vision_tls_config.jsonc` | VLESS + Vision + TLS |
| `xray_vless_xhttp_reality_config.jsonc` | VLESS + XHTTP + REALITY |
| `xray_vless_xhttp_reality-tls_config.jsonc` | VLESS + XHTTP + REALITY (nested via TLS) |
| `xray_vless_xhttp_tls_config.jsonc` | VLESS + XHTTP + TLS |
| `xray_vless_httpupgrade_tls_config.jsonc` | VLESS + HTTPUpgrade + TLS |
| `xray_trojan_raw_tls_config.jsonc` | Trojan + RAW + TLS |
| `xray_vmess_xhttp_tls_config.jsonc` | VMess + XHTTP + TLS |
| `xray_vmess_httpupgrade_tls_config.jsonc` | VMess + HTTPUpgrade + TLS |

**V2Ray-совместимые (файлы `v2ray_*.json`):**

| Файл | Протокол |
|---|---|
| `v2ray_vmess_ws_tls_config.json` | VMess + WebSocket + TLS |
| `v2ray_vless_ws_tls_config.json` | VLESS + WebSocket + TLS |
| `v2ray_vless_grpc_tls_config.json` | VLESS + gRPC + TLS |
| `v2ray_trojan_ws_tls_config.json` | Trojan + WebSocket + TLS |

---

## Рекомендуемые клиентские приложения

| Платформа | Приложение | Поддержка Reality/XHTTP |
|---|---|---|
| Android | Hiddify, NekoBox | ✅ |
| iOS | Shadowrocket, Stash | ✅ |
| Windows | v2rayN, Hiddify | ✅ |
| macOS | Hiddify, V2Box | ✅ |
| Linux | v2rayA, sing-box | ✅ |
| Роутер | OpenWRT + sing-box | ✅ |

> Для Desktop при использовании оригинального xray-core: браузер настройте через SwitchyOmega (подключить к SOCKS5 `127.0.0.1:10808` или HTTP `127.0.0.1:10809`).

---

## QR-коды

```bash
# Установить qrencode
apt install qrencode

# Сгенерировать QR из ссылки
LINK="vless://UUID@SERVER_IP:443?..."
qrencode -t ANSIUTF8 "$LINK"          # в терминале
qrencode -t PNG -o /tmp/qr.png "$LINK" # в файл

# Или через онлайн: https://qr.io/
```
