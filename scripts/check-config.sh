#!/bin/bash
# check-config.sh — валидация конфигов Xray и Nginx перед деплоем

set -euo pipefail

XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_CONFIG="${1:-/usr/local/etc/xray/config.json}"
NGINX_CONFIG="${2:-/etc/nginx/nginx.conf}"

OK=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    echo -n "  [$name] ... "
    if eval "$cmd" &>/dev/null; then
        echo "OK"
        ((OK++))
    else
        echo "FAIL"
        eval "$cmd" 2>&1 | sed 's/^/    >> /'
        ((FAIL++))
    fi
}

echo ""
echo "===== Pre-deploy Config Check ====="
echo ""

echo "-- Xray --"
check "binary exists"       "test -f $XRAY_BIN"
check "config exists"       "test -f $XRAY_CONFIG"
check "config valid"        "$XRAY_BIN -test -config $XRAY_CONFIG"

echo ""
echo "-- Nginx --"
check "binary exists"       "which nginx"
check "config exists"       "test -f $NGINX_CONFIG"
check "config valid"        "nginx -t -c $NGINX_CONFIG"
check "stream module"       "nginx -V 2>&1 | grep -q 'with-stream '"
check "realip module"       "nginx -V 2>&1 | grep -q 'http_realip_module'"
check "ssl module"          "nginx -V 2>&1 | grep -q 'http_ssl_module'"
check "v2 module"           "nginx -V 2>&1 | grep -q 'http_v2_module'"

echo ""
echo "-- Ports --"
check "port 443 free or nginx" \
    "ss -tlnp | grep :443 | grep -q nginx || ! ss -tlnp | grep -q :443"
check "port 80 accessible"     "ss -tlnp | grep -q :80 || true"

echo ""
echo "-- TLS Certificates --"
CERT_DIR="/home/tls"
if ls $CERT_DIR/*/*.crt &>/dev/null 2>&1; then
    for cert in $CERT_DIR/*/*.crt; do
        domain=$(basename $(dirname $cert))
        EXPIRE=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2)
        DAYS=$(( ($(date -d "$EXPIRE" +%s) - $(date +%s)) / 86400 ))
        echo -n "  [$domain] expires in $DAYS days ... "
        if [ $DAYS -gt 14 ]; then echo "OK"; ((OK++))
        elif [ $DAYS -gt 0 ]; then echo "WARN (expires soon!)"; ((FAIL++))
        else echo "FAIL (expired!)"; ((FAIL++))
        fi
    done
else
    echo "  (no certs found in $CERT_DIR)"
fi

echo ""
echo "-- Xray Reality keys (basic check) --"
if grep -q '"privateKey"' "$XRAY_CONFIG" 2>/dev/null; then
    KEY=$(python3 -c "
import sys, re, json
s = re.sub(r'//.*', '', open('$XRAY_CONFIG').read())
cfg = json.loads(s)
for inb in cfg.get('inbounds', []):
    rs = inb.get('streamSettings', {}).get('realitySettings', {})
    if rs.get('privateKey'):
        print(rs['privateKey'])
        break
" 2>/dev/null)
    if [ -n "$KEY" ]; then
        check "Reality key length (≥43)" "[ ${#KEY} -ge 43 ]"
    fi
fi

echo ""
echo "===== Result: $OK passed, $FAIL failed ====="
echo ""

if [ $FAIL -gt 0 ]; then
    echo "Fix the issues above before deploying."
    exit 1
else
    echo "All checks passed. Safe to deploy."
    exit 0
fi
