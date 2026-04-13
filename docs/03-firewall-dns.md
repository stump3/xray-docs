# 03 — Firewall и DNS

## DNS-записи

Набор записей зависит от выбранной архитектуры.

### Вариант A (Xray напрямую на 443, без домена)

DNS не обязателен — клиенты подключаются по IP напрямую. Subscription-endpoint Nginx работает на произвольном порту.

### Вариант B (Nginx stream, один домен)

```
your-domain.com    A     <SERVER_IP>
your-domain.com    AAAA  <SERVER_IPv6>  # если есть IPv6
```

### lxhao61 E+F+H+A (четыре домена под разные протоколы)

```
h2t.example.com    A     <SERVER_IP>    # VLESS+Vision+TLS
t2n.example.com    A     <SERVER_IP>    # Trojan+RAW+TLS
cdn.example.com    A     <SERVER_IP>    # VLESS+XHTTP+TLS (CDN-совместимый)
h3a.example.com    A     <SERVER_IP>    # HTTP/3 + XHTTP
```

### lxhao61 M+H+K+A (два домена)

```
cdn.example.com    A     <SERVER_IP>    # VLESS+XHTTP+TLS (CDN-клиенты)
h3a.example.com    A     <SERVER_IP>    # REALITY target + HTTP/3
```

### Через Cloudflare CDN

Для CDN-совместимых протоколов (XHTTP, WS, gRPC):

```
cdn.example.com    A     <SERVER_IP>    # Proxy status: Proxied (оранжевое облако)
h3a.example.com    A     <SERVER_IP>    # Proxy status: DNS only (серое облако)
```

> Reality-домен (`h3a`, `h2t`) должен быть **DNS only** — Reality несовместима с CDN-проксированием.

В Cloudflare Dashboard → Network → включить **WebSocket** (для WS) и **gRPC** (для gRPC).

### Проверка DNS

```bash
# Проверить A-запись
dig +short h3a.example.com A

# Проверить распространение (из разных мест)
curl "https://dns.google/resolve?name=h3a.example.com&type=A" | python3 -m json.tool

# Убедиться что домен ведёт на ваш IP
curl -s ifconfig.me                # ваш IP
dig +short h3a.example.com A       # должно совпадать
```

---

## Firewall

### UFW (Ubuntu)

```bash
# Базовая конфигурация
ufw default deny incoming
ufw default allow outgoing

# SSH — обязательно, иначе потеряете доступ
ufw allow 22/tcp

# Основной порт VPN
ufw allow 443/tcp
ufw allow 443/udp    # HTTP/3 (QUIC)

# HTTP для certbot / redirect
ufw allow 80/tcp

# mKCP (если используется, Вариант A)
ufw allow 2052/udp

ufw enable
ufw status verbose
```

### iptables (без UFW)

```bash
# Сохранить текущие правила
iptables-save > /etc/iptables/rules.v4

# Разрешить нужные порты
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
iptables -I INPUT -p udp --dport 443 -j ACCEPT   # HTTP/3
iptables -I INPUT -p udp --dport 2052 -j ACCEPT  # mKCP

# Запрет всего остального (после разрешений)
iptables -A INPUT -j DROP

# Сохранить
iptables-save > /etc/iptables/rules.v4
apt install iptables-persistent
```

### nftables (современный вариант, Ubuntu 22.04+)

```bash
cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        iif lo accept
        tcp dport 22 accept
        tcp dport 80 accept
        tcp dport 443 accept
        udp dport 443 accept    # HTTP/3
        udp dport 2052 accept   # mKCP
    }
    chain forward { type filter hook forward priority 0; policy drop; }
    chain output  { type filter hook output  priority 0; policy accept; }
}
EOF

systemctl enable --now nftables
nft list ruleset
```

---

## IPv6

Если сервер имеет IPv6-адрес и нужна поддержка:

### Nginx

```nginx
server {
    listen 80;
    listen [::]:80;    # добавить для IPv6
    ...
}

stream {
    server {
        listen 443;
        listen [::]:443;    # добавить для IPv6
        ...
    }
}
```

### Xray

```jsonc
{
  "listen": "::",    // слушает и IPv4, и IPv6
  "port": 443,
  ...
}
```

### Firewall (UFW + IPv6)

```bash
# Убедиться что IPv6 включён в UFW
grep IPV6 /etc/default/ufw
# IPV6=yes

ufw allow 443/tcp
ufw allow 443/udp
# UFW автоматически создаёт правила для IPv6
```

---

## Проверка сетевой конфигурации

```bash
# Что слушает на порту 443?
ss -tlnp | grep :443
ss -ulnp | grep :443

# Доступен ли порт снаружи (с другой машины или через онлайн-инструменты)
nc -zv <SERVER_IP> 443
curl -I --connect-timeout 5 https://your-domain.com

# Проверка Reality target
xray tls ping www.microsoft.com

# Проверка TLS-сертификата
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null 2>&1 \
    | openssl x509 -noout -subject -dates

# Проверка SNI routing (Nginx stream)
# Отправить ClientHello с конкретным SNI:
openssl s_client -connect <SERVER_IP>:443 -servername h3a.example.com < /dev/null
```

---

## kernel sysctl — оптимизация сети

Для высоконагруженных серверов (100+ одновременных соединений):

```bash
cat >> /etc/sysctl.d/99-xray.conf << 'EOF'
# Увеличить буферы TCP
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Увеличить очередь соединений
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# TIME_WAIT переработка
net.ipv4.tcp_tw_reuse = 1
EOF

sysctl --system

# Проверить BBR
sysctl net.ipv4.tcp_congestion_control
# net.ipv4.tcp_congestion_control = bbr
```

> BBR значительно улучшает пропускную способность при потерях пакетов. Особенно полезен при использовании mKCP.
