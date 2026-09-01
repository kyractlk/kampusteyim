#!/usr/bin/env bash
# Codemagic iOS imza — CERTIFICATE_PRIVATE_KEY (PEM veya base64 PEM).
set -uo pipefail

PROFILE_TYPE="${1:-IOS_APP_STORE}"
BUNDLE_ID="${BUNDLE_ID:-com.aystech.mtMobil}"
PEM_FILE="/tmp/codemagic_distribution_key.pem"

pem_looks_valid() {
  grep -qE 'BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY' "$1" 2>/dev/null
}

prepare_pem_file() {
  : > "$PEM_FILE"

  # 1) Dosya yolu verilmişse (nadir)
  if [ -f "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
    cp "${CERTIFICATE_PRIVATE_KEY}" "$PEM_FILE"
    chmod 600 "$PEM_FILE"
    pem_looks_valid "$PEM_FILE" && return 0
  fi

  # 2) Ayrı base64 değişkeni (Codemagic için önerilen)
  if [ -n "${CERTIFICATE_PRIVATE_KEY_BASE64:-}" ]; then
    echo "$CERTIFICATE_PRIVATE_KEY_BASE64" | tr -d '[:space:]' | base64 --decode > "$PEM_FILE" 2>/dev/null || true
    chmod 600 "$PEM_FILE"
    pem_looks_valid "$PEM_FILE" && return 0
  fi

  if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
    return 1
  fi

  local raw="$CERTIFICATE_PRIVATE_KEY"
  # Tırnak sarmalayıcıları kaldır
  raw="${raw#\"}"
  raw="${raw%\"}"
  raw="${raw#\'}"
  raw="${raw%\'}"

  # 3) Ham PEM (çok satırlı env)
  printf '%b' "$raw" > "$PEM_FILE"
  chmod 600 "$PEM_FILE"
  pem_looks_valid "$PEM_FILE" && return 0

  # 4) Literal \n ile tek satır PEM
  printf '%s' "$raw" | sed 's/\\n/\n/g' > "$PEM_FILE"
  pem_looks_valid "$PEM_FILE" && return 0

  # 5) Tek satır base64 PEM (BEGIN yok → decode dene)
  if ! grep -q 'BEGIN' "$PEM_FILE" 2>/dev/null; then
    tr -d '[:space:]' < "$PEM_FILE" | base64 --decode > "${PEM_FILE}.dec" 2>/dev/null || true
    if [ -s "${PEM_FILE}.dec" ] && pem_looks_valid "${PEM_FILE}.dec"; then
      mv "${PEM_FILE}.dec" "$PEM_FILE"
      chmod 600 "$PEM_FILE"
      return 0
    fi
    rm -f "${PEM_FILE}.dec"
  fi

  return 1
}

print_pem_help() {
  echo ""
  echo "CERTIFICATE_PRIVATE_KEY Codemagic'te geçersiz veya boş."
  echo ""
  echo "Önerilen kurulum (ios_code_signing grubu):"
  echo "  A) CERTIFICATE_PRIVATE_KEY_BASE64 = PEM dosyasının base64 (tek satır)"
  echo "     macOS:  base64 -i certificate_private_key.pem | tr -d '\\n'"
  echo "     Win PS: [Convert]::ToBase64String([IO.File]::ReadAllBytes('certificate_private_key.pem'))"
  echo ""
  echo "  B) CERTIFICATE_PRIVATE_KEY = tam PEM (-----BEGIN … PRIVATE KEY-----)"
  echo "     Not: Codemagic Secure variable çok satırlı PEM'i bazen keser → A tercih edin."
  echo ""
  echo "Mevcut değişken uzunlukları:"
  echo "  CERTIFICATE_PRIVATE_KEY: ${#CERTIFICATE_PRIVATE_KEY} karakter"
  echo "  CERTIFICATE_PRIVATE_KEY_BASE64: ${#CERTIFICATE_PRIVATE_KEY_BASE64} karakter"
}

if ! prepare_pem_file; then
  echo "ERROR: Geçerli private key PEM hazırlanamadı."
  print_pem_help
  exit 1
fi

echo "Private key PEM hazır ($(wc -c < "$PEM_FILE" | tr -d ' ') byte)"

keychain initialize

revoke_all_distribution() {
  echo "Tüm IOS_DISTRIBUTION sertifikaları listeleniyor…"
  set +e
  app-store-connect certificates list --type IOS_DISTRIBUTION --json > /tmp/dist_certs.json
  LIST_RC=$?
  set -e

  if [ "$LIST_RC" -ne 0 ] || [ ! -s /tmp/dist_certs.json ]; then
    echo "WARN: cert listesi alınamadı (rc=$LIST_RC), devam ediliyor…"
    return 0
  fi

  python3 /dev/stdin /tmp/dist_certs.json <<'PY'
import json, subprocess, sys
path = sys.argv[1]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception as e:
    print(f"WARN: JSON parse: {e}")
    sys.exit(0)
items = data if isinstance(data, list) else data.get("data", data.get("certificates", []))
for c in items:
    cid = c.get("id")
    attrs = c.get("attributes") or {}
    if not cid:
        cid = attrs.get("id")
    name = attrs.get("name") or c.get("name") or ""
    if not cid:
        continue
    print(f"Revoking IOS_DISTRIBUTION: {cid} ({name})")
    subprocess.run(
        ["app-store-connect", "certificates", "revoke", "--certificate-id", str(cid)],
        check=False,
    )
PY
}

create_signing_files() {
  echo "Cert + profil oluşturuluyor ($PROFILE_TYPE)…"
  app-store-connect fetch-signing-files "$BUNDLE_ID" \
    --type "$PROFILE_TYPE" \
    --certificate-key=@file:"$PEM_FILE" \
    --create
}

echo "iOS signing · bundle=$BUNDLE_ID · profile=$PROFILE_TYPE"

set +e
app-store-connect fetch-signing-files "$BUNDLE_ID" \
  --type "$PROFILE_TYPE" \
  --certificate-key=@file:"$PEM_FILE"
RC=$?
set -e

if [ "$RC" -eq 0 ]; then
  echo "Mevcut imza dosyaları kullanıldı."
else
  echo "Eşleşen cert yok (rc=$RC). Eski Distribution cert'ler temizlenip yenisi oluşturulacak…"
  revoke_all_distribution
  sleep 2
  set +e
  create_signing_files
  RC=$?
  set -e
  if [ "$RC" -ne 0 ]; then
    echo "ERROR: iOS imza oluşturulamadı (rc=$RC)."
    print_pem_help
    exit 1
  fi
fi

keychain add-certificates
xcode-project use-profiles
echo "iOS signing hazır ($PROFILE_TYPE)"
