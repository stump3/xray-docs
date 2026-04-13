# 02 — Управление TLS-сертификатами

> Сертификаты нужны только при использовании TLS-терминации на Nginx или Xray (Варианты B, C, D и lxhao61-E+F+H+A).  
> Вариант A и чистый REALITY (M без fallback на Nginx) **не требуют сертификатов**.

---

## Установка acme.sh

```bash
curl https://get.acme.sh | sh -s email=your@email.com
source ~/.bashrc
# или перезайти в сессию, чтобы alias acme.sh заработал
```

acme.sh устанавливается в `~/.acme.sh/` и добавляет cron-задачу для автопродления.

---

## Получение сертификата

### HTTP-01 через Nginx (рекомендуется на серверах с Nginx)

Перед выпуском сертификата порт 80 должен быть доступен. Если Nginx уже запущен и слушает :80, используйте режим `--nginx`, который временно добавляет файл валидации через Nginx без остановки сервера:

```bash
export domain=your-domain.com

~/.acme.sh/acme.sh --issue --server letsencrypt \
    -d $domain \
    --nginx \
    --keylength ec-256
```

Флаг `--nginx` автоматически обрабатывает проверку через уже запущенный Nginx.

### HTTP-01 без Nginx (standalone)

Если Nginx ещё не запущен:

```bash
~/.acme.sh/acme.sh --issue --server letsencrypt \
    -d $domain \
    --standalone \
    --keylength ec-256
```

> Порт 80 должен быть свободен. Если Xray или что-то другое занимает :80 — остановите сервис.

### HTTP-01 через webroot (стабильнее всего)

Nginx отдаёт файлы из директории, acme.sh кладёт туда challenge:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://$host$request_uri;
    }
}
```

```bash
~/.acme.sh/acme.sh --issue --server letsencrypt \
    -d $domain \
    -w /var/www/html \
    --keylength ec-256
```

---

## Установка сертификата

### Для Nginx (Варианты B, E+F+H+A)

```bash
export domain=your-domain.com
mkdir -p /home/tls/$domain

~/.acme.sh/acme.sh --install-cert -d $domain --ecc \
    --fullchain-file /home/tls/$domain/$domain.crt \
    --key-file       /home/tls/$domain/$domain.key \
    --reloadcmd      "systemctl reload nginx"
```

Флаг `--reloadcmd` автоматически выполняется при продлении — Nginx подхватывает новый сертификат без даунтайма.

### Для Xray (Вариант D — Xray терминирует TLS)

```bash
export domain=your-domain.com
mkdir -p /usr/local/etc/xray/xray_cert

~/.acme.sh/acme.sh --install-cert -d $domain --ecc \
    --fullchain-file /usr/local/etc/xray/xray_cert/xray.crt \
    --key-file       /usr/local/etc/xray/xray_cert/xray.key \
    --reloadcmd      "systemctl restart xray"

chmod +r /usr/local/etc/xray/xray_cert/xray.key
```

> Xray не поддерживает graceful reload (`systemctl reload xray` не работает), поэтому используется `restart`.

---

## Мультидоменные сертификаты

Если на сервере несколько доменов (как в lxhao61 E+F+H+A: h2t, t2n, cdn, h3a):

**Вариант 1 — отдельный сертификат на каждый домен** (рекомендуется для изоляции):

```bash
for domain in h2t.example.com t2n.example.com cdn.example.com h3a.example.com; do
    ~/.acme.sh/acme.sh --issue --server letsencrypt \
        -d $domain --nginx --keylength ec-256
    
    mkdir -p /home/tls/$domain
    ~/.acme.sh/acme.sh --install-cert -d $domain --ecc \
        --fullchain-file /home/tls/$domain/$domain.crt \
        --key-file       /home/tls/$domain/$domain.key \
        --reloadcmd      "systemctl reload nginx"
done
```

**Вариант 2 — SAN-сертификат (один на все домены)**:

```bash
~/.acme.sh/acme.sh --issue --server letsencrypt \
    -d h2t.example.com \
    -d t2n.example.com \
    -d cdn.example.com \
    -d h3a.example.com \
    --nginx --keylength ec-256
```

Все домены должны иметь A-записи, указывающие на этот сервер.

**Вариант 3 — wildcard (DNS-01)**:

```bash
~/.acme.sh/acme.sh --issue --server letsencrypt \
    -d example.com \
    -d '*.example.com' \
    --dns dns_cf \        # Cloudflare DNS API
    --keylength ec-256
```

Для Cloudflare нужны переменные `CF_Key` и `CF_Email` (или `CF_Token`).

---

## Пути сертификатов в конфигах

Используйте абсолютные пути. Структура по домену:

```
/home/tls/
├── h2t.example.com/
│   ├── h2t.example.com.crt
│   └── h2t.example.com.key
├── t2n.example.com/
│   ├── t2n.example.com.crt
│   └── t2n.example.com.key
...
```

В nginx.conf:
```nginx
ssl_certificate     /home/tls/h2t.example.com/h2t.example.com.crt;
ssl_certificate_key /home/tls/h2t.example.com/h2t.example.com.key;
```

---

## Проверка сертификатов

```bash
# Список выпущенных сертификатов
~/.acme.sh/acme.sh --list

# Детали конкретного сертификата
~/.acme.sh/acme.sh --info -d your-domain.com

# Принудительное продление (тест)
~/.acme.sh/acme.sh --renew -d your-domain.com --force

# Проверка срока действия через openssl
openssl x509 -in /home/tls/your-domain.com/your-domain.com.crt -noout -dates

# Проверка с внешнего клиента
echo | openssl s_client -connect your-domain.com:443 -servername your-domain.com 2>/dev/null \
    | openssl x509 -noout -dates
```

---

## Автопродление

acme.sh автоматически добавляет cron-задачу при установке. Проверка:

```bash
crontab -l | grep acme
# 0 0 * * * "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" > /dev/null
```

Сертификаты продлеваются за 30 дней до истечения (Let's Encrypt выдаёт на 90 дней).

Тест автопродления:
```bash
~/.acme.sh/acme.sh --cron --home ~/.acme.sh
```

---

## Конфигурация TLS в Nginx

Рекомендуемые cipher suites для ECC-сертификата:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
```

Для RSA-сертификата — заменить `ECDSA` на `RSA`.

Для Trojan+TLS (протокол F) намеренно используются non-AES cipher suites, чтобы fingerprint отличался от VLESS+Vision:

```nginx
# Только для Trojan inbound в Xray (tlsSettings):
"minVersion": "1.2",
"maxVersion": "1.2",
"cipherSuites": "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256:TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256"
```

---

## Устранение проблем с сертификатами

**`cert not yet valid` или `cert expired`** — обновите сертификат вручную:
```bash
~/.acme.sh/acme.sh --renew -d your-domain.com --force
```

**`Connection refused` на порту 80** — проверьте, что Nginx запущен и слушает :80:
```bash
ss -tlnp | grep :80
```

**`Timeout` при HTTP-01 валидации** — порт 80 закрыт файрволом:
```bash
ufw allow 80/tcp
# или
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
```

**Nginx не перезагружается после продления** — проверьте `reloadcmd`:
```bash
~/.acme.sh/acme.sh --info -d your-domain.com | grep ReloadCmd
```
