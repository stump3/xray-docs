# 06 — Troubleshooting

## Диагностика первым делом

```bash
# Статус сервисов
systemctl status xray nginx

# Последние ошибки Xray
journalctl -u xray -n 100 --no-pager | grep -E 'error|fail|warn'
tail -f /var/log/xray/error.log

# Последние ошибки Nginx
journalctl -u nginx -n 50 --no-pager
tail -f /var/log/nginx/error.log

# Что слушает на порту 443
ss -tlnp | grep :443

# Валидация конфига Nginx перед рестартом
nginx -t

# Валидация конфига Xray
xray -test -config /usr/local/etc/xray/config.json
```

---

## Xray не запускается

### Ошибка: `address already in use: 443`

Порт занят другим процессом:

```bash
ss -tlnp | grep :443
# Найти PID процесса и остановить его
kill <PID>
# или
systemctl stop nginx   # если Nginx занял 443 раньше Xray
```

В Вариантах B/C Nginx должен запускаться первым и занимать 443. Xray слушает только на localhost (127.0.0.1:8443, :5443 и т.д.).

### Ошибка: `failed to read config`

```bash
# Проверить синтаксис JSONC вручную (удалить комментарии и проверить)
cat /usr/local/etc/xray/config.json | python3 -c "
import sys, re, json
s = re.sub(r'//.*', '', sys.stdin.read())
json.loads(s)
print('JSON valid')
"
```

Типичные причины: лишняя запятая перед `}`, незакрытая скобка, неправильные кавычки.

### Ошибка: `reality: private key invalid`

Ключ сгенерирован некорректно. Перегенерировать:

```bash
xray x25519
# Вставить Private key в realitySettings.privateKey на сервере
# Вставить Public key в realitySettings.publicKey на клиенте
```

---

## Nginx не запускается

### Ошибка: `unknown directive "stream"`

Nginx собран без stream-модуля. Нужна переустановка из mainline-репозитория с `--with-stream`.

```bash
nginx -V 2>&1 | grep stream
# Если пусто — модуль отсутствует
```

### Ошибка: `ssl_reject_handshake is not allowed here`

Версия Nginx < 1.19.4. Удалите эту директиву из конфига или обновите Nginx.

### Ошибка: `http2 directive is duplicate`

В конфиге одновременно присутствуют `listen ... http2` (старый синтаксис) и `http2 on;` (новый, Nginx ≥ 1.25.1). Оставьте только один вариант в соответствии с вашей версией.

### Nginx запустился, но 443 всё равно не работает

```bash
# Проверить — stream слушает 443?
ss -tlnp | grep :443 | grep nginx

# Проверить конфиг stream
nginx -T | grep -A 30 'stream {'
```

---

## Клиент не подключается

### Reality: `failed to read target: io timeout`

Xray не может достучаться до target-домена (microsoft.com или вашего Nginx):

```bash
# Тест прямого соединения с target
curl -I --connect-timeout 5 https://www.microsoft.com

# Для собственного Nginx target (M+H+K+A):
curl -k -I https://127.0.0.1:8443 -H "Host: h3a.example.com"
```

### Reality: клиент подключается, но получает страницу decoy-сайта

Клиент использует неправильный `publicKey` или `shortId`. Проверьте subscription link.

### XHTTP: `path not found` или `404`

Путь в конфиге Xray (`xhttpSettings.path`) не совпадает с путём в `location` Nginx:

```bash
# Nginx location должен точно совпадать с path в Xray xhttpSettings
grep -n 'VLSpdG9k\|path' /usr/local/etc/xray/config.json
grep -n 'VLSpdG9k' /etc/nginx/nginx.conf
```

### WebSocket/XHTTP через Cloudflare: `502 Bad Gateway`

```bash
# В Cloudflare Dashboard → Network:
# - WebSocket: ON
# - gRPC: ON (если используется gRPC backend)

# Проверить что Nginx проксирует WebSocket правильно:
# Должны быть заголовки:
# proxy_http_version 1.1;
# proxy_set_header Upgrade $http_upgrade;
# proxy_set_header Connection "upgrade";
```

### PROXY protocol: клиент получает `connection reset`

Если Nginx stream включает `proxy_protocol on`, то все upstream должны принимать PROXY protocol. Если Xray inbound не имеет `"acceptProxyProtocol": true` — соединение сбрасывается.

```jsonc
// В streamSettings Xray inbound добавить:
"rawSettings": {
  "acceptProxyProtocol": true
}
```

Или отключить PROXY protocol в Nginx stream:
```nginx
server {
    listen 443;
    ssl_preread on;
    # proxy_protocol on;  ← закомментировать
    proxy_pass $backend;
}
```

---

## Реальный IP не логируется

### Симптом: в логах Nginx везде `127.0.0.1`

При использовании Nginx stream PROXY protocol нужно настроить `real_ip_header` в HTTP-блоке:

```nginx
server {
    listen 127.0.0.1:8443 ssl proxy_protocol;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;
    ...
}
```

Проверьте что Nginx собран с `--with-http_realip_module`:
```bash
nginx -V 2>&1 | grep realip
```

### Симптом: в логах CDN-IP вместо клиентского IP

При использовании Cloudflare добавьте в Nginx:

```nginx
map $http_x_forwarded_for $client_ip {
    ""  $remote_addr;
    "~*(?P<firstAddr>([0-9a-f]{0,4}:){1,7}[0-9a-f]{1,4}|([0-9]{1,3}\.){3}[0-9]{1,3})$" $firstAddr;
}
log_format main '$client_ip - $remote_user [$time_local] "$request" ...';
```

---

## Производительность

### Высокая нагрузка на CPU

```bash
# Посмотреть сколько соединений держит Xray
ss -anp | grep xray | wc -l

# Включить BBR если не включён
sysctl net.ipv4.tcp_congestion_control
# Должно быть: bbr

# Проверить LimitNOFILE в systemd unit
systemctl show xray | grep LimitNOFILE
# Должно быть: LimitNOFILE=1000000
```

### Медленная скорость через WebSocket/gRPC

WebSocket и gRPC по своей природе медленнее чем VLESS+Vision+REALITY. Если нужна максимальная скорость — используйте Reality (Вариант A или M в lxhao61).

---

## Полезные команды

```bash
# Перезапустить Xray с проверкой конфига
xray -test -config /usr/local/etc/xray/config.json && systemctl restart xray

# Graceful reload Nginx (без разрыва соединений)
systemctl reload nginx

# Показать все активные соединения на 443
ss -antp | grep :443

# Проверить TLS-хендшейк с конкретным SNI
openssl s_client -connect <SERVER_IP>:443 -servername h3a.example.com < /dev/null 2>&1 | head -30

# Тест Reality target
xray tls ping www.microsoft.com

# Генерация тестового трафика (проверка пропускной способности)
curl -o /dev/null https://your-domain.com/bigfile --max-time 30 -w "%{speed_download}\n"
```

---

## Лог-файлы и уровни логирования

### Xray

```jsonc
"log": {
  "loglevel": "warning",   // none | error | warning | info | debug
  "error":  "/var/log/xray/error.log",
  "access": "/var/log/xray/access.log"
}
```

При диагностике временно поставьте `"info"`, после решения проблемы верните `"warning"`. Уровень `"debug"` очень многословен — только для разработки.

### Nginx

```nginx
error_log /var/log/nginx/error.log;   # уровень: warn (по умолчанию)
# Для диагностики:
error_log /var/log/nginx/error.log info;
```

### Ротация логов

```bash
# Проверить что logrotate настроен
cat /etc/logrotate.d/nginx
ls /etc/logrotate.d/ | grep xray
# Если нет — создать:
cat > /etc/logrotate.d/xray << 'EOF'
/var/log/xray/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        systemctl kill -s USR1 xray
    endscript
}
EOF
```
