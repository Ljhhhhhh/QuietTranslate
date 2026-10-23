#!/bin/zsh
# 更新私钥只存于钥匙串；已有公钥时禁止静默更换身份。
set -eu
cd "$(dirname "$0")/.."
swift package resolve
TOOL=.build/artifacts/sparkle/Sparkle/bin/generate_keys
ACCOUNT=local.quiettranslate.sparkle
PUBLIC_KEY=Resources/UpdatePublicKey.txt
if [[ -s "$PUBLIC_KEY" ]]; then
    EXISTING=$("$TOOL" --account "$ACCOUNT" -p)
    if [[ "$EXISTING" != "$(cat "$PUBLIC_KEY")" ]]; then
        echo '更新密钥与项目公钥不一致，请恢复原钥匙串密钥。' >&2
        exit 1
    fi
else
    "$TOOL" --account "$ACCOUNT"
    KEY=$("$TOOL" --account "$ACCOUNT" -p)
    printf '%s\n' "$KEY" > "$PUBLIC_KEY"
fi
echo '更新签名已就绪。请保留钥匙串中 local.quiettranslate.sparkle 账号的私钥。'
