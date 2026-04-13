#!/bin/bash
# gen-keys.sh — генерация всех ключей для Xray-сервера
# Использование: bash gen-keys.sh [количество_shortId] [количество_пользователей]

SHORTID_COUNT=${1:-3}
USER_COUNT=${2:-1}

echo "===== Xray Key Generator ====="
echo ""

# Reality keypair
echo "--- Reality Keypair (один раз на сервер) ---"
KEYPAIR=$(xray x25519 2>/dev/null || /usr/local/bin/xray x25519)
PRIVATE_KEY=$(echo "$KEYPAIR" | grep 'Private key' | awk '{print $NF}')
PUBLIC_KEY=$(echo  "$KEYPAIR" | grep 'Public key'  | awk '{print $NF}')
echo "  Server privateKey:  $PRIVATE_KEY"
echo "  Client publicKey:   $PUBLIC_KEY"
echo ""

# Short IDs
echo "--- Short IDs (вставить в realitySettings.shortIds на сервере) ---"
echo -n '  shortIds: ["'
for i in $(seq 1 $SHORTID_COUNT); do
    SID=$(openssl rand -hex 8)
    echo -n "$SID"
    if [ $i -lt $SHORTID_COUNT ]; then echo -n '", "'; fi
    # Сохранить последний для вывода клиенту
    LAST_SID="$SID"
done
echo '"]'
echo "  (клиенту передать любой из shortIds — например первый)"
echo ""

# User UUIDs
echo "--- User UUIDs ---"
UUIDS=()
for i in $(seq 1 $USER_COUNT); do
    UUID=$(xray uuid 2>/dev/null || /usr/local/bin/xray uuid)
    UUIDS+=("$UUID")
    echo "  Пользователь $i: $UUID"
done
echo ""

# Subscription link template (VLESS+XHTTP+Reality)
echo "--- Subscription Link Template (VLESS+XHTTP+Reality) ---"
echo "  Замените SERVER_IP и PATH на реальные значения:"
echo ""
echo "  vless://${UUIDS[0]}@SERVER_IP:443\\"
echo "    ?security=reality\\"
echo "    &encryption=none\\"
echo "    &pbk=$PUBLIC_KEY\\"
echo "    &fp=chrome\\"
echo "    &type=xhttp\\"
echo "    &path=/PATH\\"
echo "    &sni=www.microsoft.com\\"
echo "    &sid=$LAST_SID\\"
echo "    #user1"
echo ""

# Summary for config.json
echo "--- Вставить в xray.jsonc (realitySettings) ---"
echo '  "privateKey": "'$PRIVATE_KEY'",'
echo '  "shortIds": ["'$(openssl rand -hex 4)'", "'$(openssl rand -hex 8)'"]'
echo ""
echo "  Примечание: shortIds на клиенте должен совпадать с одним из shortIds на сервере."
