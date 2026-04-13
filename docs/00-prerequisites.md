# 00 — Требования и установка

## Требования к серверу

### Минимальные

| Параметр | Минимум | Рекомендуется |
|---|---|---|
| ОС | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| CPU | 1 vCPU | 2 vCPU |
| RAM | 512 MB | 1 GB |
| Диск | 10 GB | 20 GB |
| IPv4 | Обязателен | — |
| IPv6 | Опционально | Желательно |

### Сетевые требования

- Порт **443 TCP** — внешний, доступен клиентам
- Порт **443 UDP** — если используется HTTP/3 (Nginx QUIC)
- Порт **80 TCP** — для HTTP→HTTPS редиректа и HTTP-01 валидации сертификатов
- Порт **2052 UDP** — если используется mKCP (Вариант A)

> Все остальные порты (8443, 7443, 5443, 6443, 2023 и т.д.) — только localhost, снаружи недоступны.

---

## Установка Xray

### Официальный скрипт (рекомендуется)

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

Устанавливает:
- Бинарник: `/usr/local/bin/xray`
- Конфиг: `/usr/local/etc/xray/config.json`
- Ресурсы (geoip, geosite): `/usr/local/share/xray/`
- systemd unit: `/etc/systemd/system/xray.service`
- Логи: `/var/log/xray/`

### Проверка установки

```bash
xray version
# Xray 25.x.x (XTLS/Xray-core) ...

systemctl status xray
```

### Обновление

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
systemctl restart xray
```

---

## Установка Nginx

> Стандартный Nginx из apt-репозиториев **не содержит** ряд модулей. Для полного функционала нужен пакет из официального репозитория Nginx.

### Проверка наличия нужных модулей

```bash
nginx -V 2>&1 | tr ' ' '\n' | grep -E 'stream|realip|ssl|v2|v3'
```

Нужны все следующие:
- `--with-stream` — SNI routing (Варианты B, E+F+H+A)
- `--with-stream_ssl_preread_module` — чтение SNI без расшифровки
- `--with-http_ssl_module` — HTTPS
- `--with-http_v2_module` — HTTP/2
- `--with-http_v3_module` + QUIC-совместимая SSL-библиотека — HTTP/3 (опционально)
- `--with-http_realip_module` — получение реального IP из PROXY protocol

### Установка из официального репозитория Nginx

```bash
# Добавить GPG ключ
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# Добавить репозиторий (mainline — для HTTP/3 и новых функций)
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list

sudo apt update
sudo apt install nginx
```

### Установка из репозитория с поддержкой QUIC (HTTP/3)

Nginx ≥ v1.25.0 с QUIC-поддержкой доступен в пакете `nginx-quic`:

```bash
# Официальный PPA с поддержкой QUIC
add-apt-repository ppa:ondrej/nginx-quic
apt update && apt install nginx
```

> Альтернатива: собрать из исходников с `--with-http_v3_module` и OpenSSL 3.x или BoringSSL.

### Проверка версии

```bash
nginx -v
# nginx version: nginx/1.27.x
```

---

## Структура файлов конфигурации

### Xray

```
/usr/local/bin/xray                     # бинарник
/usr/local/etc/xray/
├── config.json   (или config.jsonc)    # основной конфиг
└── xray_cert/                          # TLS-сертификаты (если Xray терминирует TLS)
    ├── xray.crt
    └── xray.key
/usr/local/share/xray/
├── geoip.dat
└── geosite.dat
/var/log/xray/
├── access.log
└── error.log
```

> Xray нативно поддерживает JSONC (JSON с комментариями `//`). Называйте файл `.jsonc` — это удобно для документирования конфигов.

### Nginx

```
/etc/nginx/
├── nginx.conf                          # главный конфиг
├── conf.d/                             # дополнительные server blocks
└── mime.types

/home/tls/<domain>/                     # сертификаты (рекомендуемое расположение)
├── <domain>.crt
└── <domain>.key

/var/www/html/                          # decoy-сайт
/var/log/nginx/
├── access.log
└── error.log
```

---

## Генерация ключей и идентификаторов

Выполняется один раз при первоначальной настройке.

```bash
# UUID клиента (один на каждого пользователя)
xray uuid
# Пример: edfd12f5-acc9-49dc-9d67-efec7a2f8ff4

# Reality keypair (одна пара на сервер)
xray x25519
# Private key: iD0BftokWqJ6UhCzVBlK2sI5OjmfWks0PAdU3SLWKUw   ← на сервере
# Public key:  abc123...                                        ← клиентам

# Short ID (можно несколько, для разных клиентов)
openssl rand -hex 8
# Пример: a1b2c3d4e5f6a7b8
```

> Используйте скрипт `scripts/gen-keys.sh` для генерации и форматирования всех ключей сразу.

---

## Выбор decoy-домена для Reality

При использовании Reality с чужим сайтом (Вариант A, стандартный):

**Требования к сайту:**
- Зарубежный домен (не под блокировкой)
- Поддержка TLSv1.3
- Поддержка HTTP/2
- Домен без редиректов на другой домен

**Проверка:**
```bash
xray tls ping www.microsoft.com
# Должно вернуть TLSv1.3 + h2
```

**Проверенные домены:** `www.microsoft.com`, `www.apple.com`, `dl.google.com`, `addons.mozilla.org`

**Не использовать:** домены с Cloudflare CDN в качестве target (Reality не работает через CDN).

---

## Проверка готовности сервера

```bash
# Порт 443 свободен?
ss -tlnp | grep :443
# Должно быть пусто до запуска Xray/Nginx

# stream-модуль Nginx собран?
nginx -V 2>&1 | grep -o 'stream'

# Xray работает?
systemctl is-active xray

# Nginx работает?
systemctl is-active nginx

# Логи Xray
journalctl -u xray -n 50 --no-pager

# Тест конфига Nginx
nginx -t
```
