# 07 — Операции: ротация ключей, бэкап, мониторинг

## Ротация UUID клиента

Безопасное удаление клиента без даунтайма:

```bash
# 1. Сгенерировать новый UUID
NEW_UUID=$(xray uuid)
echo "Новый UUID: $NEW_UUID"

# 2. Добавить новый UUID в clients[] рядом со старым
# В config.json:
# "clients": [
#   { "id": "OLD-UUID", "email": "user@example.com" },   ← оставить пока
#   { "id": "NEW-UUID", "email": "user@example.com" }    ← добавить
# ]

# 3. Перезапустить Xray (клиент ещё работает на старом UUID)
systemctl restart xray

# 4. Обновить клиентский конфиг / subscription link

# 5. После перехода клиента — удалить старый UUID из конфига
# Перезапустить Xray ещё раз
systemctl restart xray
```

## Ротация Reality keypair

> Смена Reality ключей требует одновременного обновления всех клиентов.

```bash
# 1. Сгенерировать новую пару ключей
xray x25519
# Private key: <NEW_PRIVATE_KEY>
# Public key:  <NEW_PUBLIC_KEY>

# 2. Запланировать maintenance window

# 3. Обновить privateKey в config.json сервера
# 4. Перезапустить Xray
systemctl restart xray

# 5. Обновить publicKey во всех клиентских конфигах
# 6. Обновить subscription endpoint
```

## Ротация Short ID

Short ID может быть добавлен новый, а старый удалён:

```jsonc
"shortIds": [
  "a1b2c3d4",        // старый — пока оставляем
  "e5f6a7b8"         // новый — добавляем
]
```

После того как все клиенты переключились на новый — удалить старый из массива.

---

## Добавление нового пользователя

```bash
# Сгенерировать UUID
NEW_UUID=$(xray uuid)

# Добавить в clients[] в config.json:
# { "id": "$NEW_UUID", "email": "newuser@example.com" }

# Перезапустить Xray
systemctl restart xray

# Сгенерировать subscription link (пример для VLESS+XHTTP+Reality)
cat << EOF
vless://${NEW_UUID}@SERVER-IP:443?security=reality&encryption=none&pbk=PUBLIC-KEY&fp=chrome&type=xhttp&path=/yourpath&sni=www.microsoft.com&sid=SHORT-ID#newuser
EOF
```

---

## Бэкап

### Что бэкапить

```
/usr/local/etc/xray/              # конфиги и сертификаты Xray
/etc/nginx/nginx.conf             # конфиг Nginx
/home/tls/                        # TLS-сертификаты
~/.acme.sh/                       # acme.sh аккаунт и ключи
/etc/systemd/system/xray.service  # кастомный unit (если менялся)
```

### Скрипт бэкапа

```bash
#!/bin/bash
BACKUP_DIR="/root/backups"
DATE=$(date +%Y%m%d_%H%M%S)
ARCHIVE="$BACKUP_DIR/xray-backup-$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

tar czf "$ARCHIVE" \
    /usr/local/etc/xray/ \
    /etc/nginx/nginx.conf \
    /home/tls/ \
    ~/.acme.sh/ \
    2>/dev/null

echo "Backup: $ARCHIVE ($(du -sh $ARCHIVE | cut -f1))"

# Удалить бэкапы старше 30 дней
find "$BACKUP_DIR" -name "xray-backup-*.tar.gz" -mtime +30 -delete
```

Добавить в cron:
```bash
crontab -e
# 0 3 * * 0 /root/backup-xray.sh  # каждое воскресенье в 03:00
```

### Восстановление

```bash
# Остановить сервисы
systemctl stop xray nginx

# Восстановить конфиги
tar xzf /root/backups/xray-backup-<DATE>.tar.gz -C /

# Запустить сервисы
systemctl start nginx xray

# Проверить
systemctl status xray nginx
```

---

## Мониторинг

### Проверка живости (health check)

```bash
# Скрипт мониторинга — запускать через cron или systemd timer
#!/bin/bash
if ! systemctl is-active --quiet xray; then
    echo "Xray DOWN — перезапускаем" >&2
    systemctl restart xray
    # Сюда можно добавить алерт: curl telegram webhook, etc.
fi

if ! systemctl is-active --quiet nginx; then
    echo "Nginx DOWN — перезапускаем" >&2
    systemctl restart nginx
fi
```

### Статистика трафика (встроенная в Xray)

Включается в конфиге (см. `configs/other/traffic.json`):

```bash
# После настройки traffic.json и перезапуска:
# Запустить скрипт статистики (от root):
chmod +x /root/xray.sh
./xray.sh

# Пример вывода:
# user@example.com    ↑ 1.23 GB  ↓ 45.67 GB
```

### Мониторинг соединений

```bash
# Активные соединения на 443
watch -n 5 'ss -antp | grep :443 | wc -l'

# Топ IP по количеству соединений
ss -antp | grep :443 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head 20

# Трафик в реальном времени
apt install iftop
iftop -i eth0 -f 'port 443'
```

### Проверка сертификата (мониторинг истечения)

```bash
# Добавить в crontab для алерта за 14 дней до истечения:
#!/bin/bash
DOMAIN="your-domain.com"
CERT="/home/tls/$DOMAIN/$DOMAIN.crt"
EXPIRE_DATE=$(openssl x509 -in "$CERT" -noout -enddate | cut -d= -f2)
EXPIRE_EPOCH=$(date -d "$EXPIRE_DATE" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( ($EXPIRE_EPOCH - $NOW_EPOCH) / 86400 ))

if [ $DAYS_LEFT -lt 14 ]; then
    echo "WARN: Сертификат $DOMAIN истекает через $DAYS_LEFT дней!"
fi
```

---

## Обновление geoip/geosite

```bash
# Скачать свежие базы
curl -Lo /usr/local/share/xray/geoip.dat \
    https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat

curl -Lo /usr/local/share/xray/geosite.dat \
    https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat

systemctl restart xray
```

Добавить в cron для ежемесячного обновления:
```
0 2 1 * * curl -Lo /usr/local/share/xray/geoip.dat https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat && systemctl restart xray
```

---

## Миграция между вариантами

### Вариант A → Вариант B

1. Установить Nginx с stream-модулем
2. Скопировать конфиг из `configs/variant-b/`
3. В Xray конфиге изменить `"listen": "0.0.0.0"` на `"listen": "127.0.0.1"` и сменить порт с 443 на 8443
4. Добавить `"acceptProxyProtocol": true` если используется PROXY protocol
5. Запустить Nginx (теперь он займёт 443), запустить Xray

### Вариант D → Вариант B/C (добавление CDN-протоколов)

Вариант D уже имеет VLESS+Vision+TLS inbound. Добавить CDN-протоколы:

1. Добавить в Xray конфиг новые inbound (WS, gRPC, XHTTP) на localhost-портах
2. Перейти на Nginx stream SNI routing
3. Добавить upstream для нового протокола в Nginx stream
4. Добавить location для нового протокола в Nginx HTTPS server block
5. Перезапустить оба сервиса
