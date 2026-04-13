# 05 — Панели управления: Marzban и 3x-ui

Панели автоматизируют управление пользователями, генерируют Xray-конфиги и subscription-ссылки. При использовании панели ручной `config.json` не нужен — панель генерирует его сама.

---

## Сравнение панелей

| | Marzban | 3x-ui |
|---|---|---|
| Язык | Python (FastAPI) | Go |
| Reality | ✅ | ✅ |
| XHTTP | ✅ | ✅ |
| WS/gRPC | ✅ | ✅ |
| Sub-links | ✅ Автоматические | ✅ Автоматические |
| Multi-node | ✅ (Marzban-node) | ⚡ Ограниченно |
| API | ✅ REST API | ✅ |
| Развитие | Активное | Активное (fork x-ui) |
| Память | ~200 MB | ~50 MB |

---

## Marzban

### Установка

```bash
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban/raw/master/script.sh)" @ install
```

После установки:
- Панель: `http://SERVER_IP:8000/dashboard`
- Конфиг: `/opt/marzban/.env`
- Xray конфиг: `/var/lib/marzban/xray_config.json` (генерируется панелью)

### Первоначальная настройка

```bash
# Создать admin-пользователя
marzban cli admin create --sudo

# Применить конфиг
marzban restart
```

### Интеграция с Nginx (вынести панель за reverse proxy)

```nginx
# В Nginx HTTPS server block (Вариант B или lxhao61):
location /dashboard/ {
    proxy_pass http://127.0.0.1:8000/dashboard/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}

location /api/ {
    proxy_pass http://127.0.0.1:8000/api/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

### Настройка Reality в Marzban

В панели → Hosts → Add Host:
- Protocol: VLESS
- Transport: TCP
- Security: Reality
- SNI: `www.microsoft.com`
- Fingerprint: `chrome`
- Reality Public Key: вставить из `xray x25519`
- Short ID: вставить из `openssl rand -hex 8`

### Конфиг inbound для Marzban (совместим с Вариантом D)

```json
{
  "tag": "VLESS_TCP_REALITY",
  "listen": "0.0.0.0",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none",
    "fallbacks": []
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "target": "www.microsoft.com:443",
      "serverNames": ["www.microsoft.com"],
      "privateKey": "PRIVATE_KEY",
      "shortIds": ["SHORT_ID"]
    }
  }
}
```

---

## 3x-ui

### Установка

```bash
bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
```

После установки:
- Панель: `http://SERVER_IP:2053/`
- Login/password задаются при установке
- Конфиг: `/usr/local/x-ui/`

### Смена порта панели (безопасность)

```bash
x-ui
# → Settings → Panel Port
```

Рекомендуется вынести панель за Nginx HTTPS reverse proxy и закрыть порт 2053 для внешних IP:

```bash
ufw deny 2053/tcp  # только после настройки Nginx proxy
```

```nginx
location /panel/ {
    proxy_pass http://127.0.0.1:2053/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

### Настройка Reality в 3x-ui

Панель → Inbounds → Add Inbound:
- Protocol: VLESS
- Transmission: TCP
- Security: Reality
- uTLS: chrome
- Dest: `www.microsoft.com:443`
- SNI: `www.microsoft.com`
- Генерировать keypair кнопкой в интерфейсе

---

## Архитектурная совместимость

Обе панели работают поверх **Варианта D** без каких-либо изменений Nginx-конфига — панель заменяет только CLI-инструменты управления пользователями.

| Архитектурный вариант | Marzban | 3x-ui |
|---|---|---|
| Вариант A (Reality, без домена) | ✅ | ✅ |
| Вариант B (Nginx stream) | ✅ | ✅ |
| Вариант C (Fallbacks All-in-One) | ✅ | ✅ |
| Вариант D (Self-SNI) | ✅ Нативно | ✅ Нативно |
| lxhao61 M+H+K+A | ✅ (ручной xray_config) | ✅ (ручной xray_config) |

Для lxhao61-паттернов: используйте панель в режиме "custom xray config" — загрузите готовый `xray.jsonc` из `configs/lxhao61-*/` и добавляйте пользователей через API или UI панели.
