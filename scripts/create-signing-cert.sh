#!/usr/bin/env bash
# 一次性创建「稳定自签名代码签名证书」——TCC 授权跨版本持久的根基。
# 产物（.temp/ 已 gitignore）：.temp/signing/{cert.pem,key.pem,selfsign.p12,Makefile.local}，
# 并自动把 Makefile.local 拷到仓库根（gitignored），此后 `make app` 即稳定签名。
# 用法：bash scripts/create-signing-cert.sh
set -euo pipefail

CN="GiveMeABreak Release"
DAYS=3650
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.temp/signing"

log() { printf '==> %s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

command -v openssl >/dev/null || die "未找到 openssl（Command Line Tools 自带：xcode-select --install）"
command -v security >/dev/null || die "未找到 security（macOS 自带）"
mkdir -p "$OUT_DIR"

# 幂等护栏：同名身份已存在则拒绝重建（重建 = 换身份 = TCC 授权再次失效）
# 注意不带 -v：-v 只列「已受信任」的身份，未完成信任步骤的会漏检
if security find-identity -p codesigning 2>/dev/null | grep -Fq "\"$CN\""; then
  log "已存在名为「${CN}」的代码签名身份，无需重建（如需查看：security find-identity -v -p codesigning）"
  exit 0
fi

log "生成密钥对与自签名证书（RSA 3072 / ${DAYS} 天 / codeSigning EKU）…"
# 经 config 文件声明扩展：-addext 在 macOS CLT 的 LibreSSL 上不可用，config 写法 OpenSSL/LibreSSL 双兼容
CNF="$OUT_DIR/openssl.cnf"
cat > "$CNF" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_code
prompt = no
[dn]
CN = $CN
[v3_code]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
EOF
openssl req -x509 -newkey rsa:3072 -nodes -days "$DAYS" -config "$CNF" \
  -keyout "$OUT_DIR/key.pem" -out "$OUT_DIR/cert.pem"

log "设置 p12 导出密码（不回显；本机导入与 GitHub secrets 配置共用）…"
read -rsp "p12 密码: " P12_PASS; echo
[ -n "$P12_PASS" ] || die "密码不能为空（p12 内含私钥，必须密码保护）"

log "打包 p12…"
openssl pkcs12 -export -inkey "$OUT_DIR/key.pem" -in "$OUT_DIR/cert.pem" \
  -name "$CN" -passout "pass:$P12_PASS" -out "$OUT_DIR/selfsign.p12"

log "导入 login keychain（并授权 /usr/bin/codesign 访问私钥）…"
security import "$OUT_DIR/selfsign.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$P12_PASS" -T /usr/bin/codesign

log "设置 code signing 信任（需要管理员密码）…"
if ! sudo security add-trusted-cert -d -r trustRoot -p codeSign \
      -k /Library/Keychains/System.keychain "$OUT_DIR/cert.pem"; then
  echo "⚠️  自动信任未完成（多见于非交互终端），请手动执行：" >&2
  echo "    sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain $OUT_DIR/cert.pem" >&2
fi

log "写入 Makefile.local（gitignored，仓库根已有同名文件时跳过）…"
if [ ! -f "$ROOT_DIR/Makefile.local" ]; then
  printf 'SIGNING_IDENTITY := %s\n' "$CN" > "$ROOT_DIR/Makefile.local"
else
  log "仓库根 Makefile.local 已存在，保持不动"
fi

log "验证签名身份（应列出一条 valid identity）…"
security find-identity -v -p codesigning | grep -F "$CN" || {
  echo "⚠️  身份尚未生效——通常因信任步骤未完成，请执行上方手动命令后重试本脚本（幂等）。" >&2
}

cat <<EOF

✅ 完成。后续步骤：
  1. 本机：仓库根 Makefile.local 已就绪，此后 \`make app\` 自动使用稳定签名（TCC 授权跨版本持久）。
  2. CI（GitHub 仓库设置，一次性）：
     - Secret  MACOS_SELFSIGN_P12     ← 终端执行：base64 -i $OUT_DIR/selfsign.p12 | pbcopy
     - Secret  MACOS_SELFSIGN_P12_PWD ← 本次输入的 p12 密码
     - Secret  KEYCHAIN_PASSWORD      ← 任意强密码（CI 临时 keychain 用）
     - Variable SELFSIGN_IDENTITY     ← $CN
  3. 备份：请把 $OUT_DIR/selfsign.p12 与密码存入安全位置——
     私钥丢失/更换 = 签名身份变更，TCC 授权需重新授予一次。

⚠️  从旧 ad-hoc 构建升级而来时，TCC 权限需重新授权一次（此后跨版本持久）。
EOF
