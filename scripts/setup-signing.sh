#!/bin/zsh
# 一次性创建本机身份；后续打包仅复用钥匙串中的证书。
set -eu
IDENTITY='QuietTranslate Local Signing'
KEYCHAIN=$(security default-keychain -d user | tr -d '"' | sed 's/^ *//')
if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "签名证书已存在，保留原身份：$IDENTITY"
    exit 0
fi
umask 077
export QT_SIGNING_PASSWORD=$(openssl rand -hex 24)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = signing
prompt = no
[dn]
CN = QuietTranslate Local Signing
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
# 系统 LibreSSL 生成兼容钥匙串的 PKCS#12；私钥只在临时目录中短暂存在。
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/signing.p12" -descert -passout env:QT_SIGNING_PASSWORD
security import "$WORK/signing.p12" -k "$KEYCHAIN" -P "$QT_SIGNING_PASSWORD" -T /usr/bin/codesign
echo "已创建本机签名身份：$IDENTITY。请保留钥匙串中的证书及私钥。"
