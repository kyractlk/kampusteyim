#!/usr/bin/env bash
# Codemagic iOS imza — CERTIFICATE_PRIVATE_KEY PEM ile yeni Distribution cert + profil.
set -uo pipefail

PROFILE_TYPE="${1:-IOS_APP_STORE}"
BUNDLE_ID="${BUNDLE_ID:-com.aystech.mtMobil}"

if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  echo "ERROR: CERTIFICATE_PRIVATE_KEY eksik (ios_code_signing grubu)."
  exit 1
fi

PEM_FILE="/tmp/codemagic_distribution_key.pem"
# PEM çok satırlı olabilir; env'den dosyaya yaz
printf '%b' "$CERTIFICATE_PRIVATE_KEY" > "$PEM_FILE"
# \n escape edilmiş tek satır PEM desteği
if ! grep -q "BEGIN PRIVATE KEY" "$PEM_FILE" 2>/dev/null; then
  echo "$CERTIFICATE_PRIVATE_KEY" | tr '\\n' '\n' > "$PEM_FILE"
fi
chmod 600 "$PEM_FILE"

if ! grep -q "BEGIN PRIVATE KEY" "$PEM_FILE"; then
  echo "ERROR: CERTIFICATE_PRIVATE_KEY geçerli PEM değil (BEGIN PRIVATE KEY yok)."
  exit 1
fi

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

# Önce mevcut eşleşen cert dene (hızlı yol)
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
    echo ""
    echo "Kontrol listesi:"
    echo "  • Codemagic → ios_code_signing → CERTIFICATE_PRIVATE_KEY tam PEM mi?"
    echo "  • developer.apple.com → Certificates → Distribution cert'leri manuel revoke"
    echo "  • App Store Connect API key (AYSCODEMAGIC) Admin rolünde mi?"
    exit 1
  fi
fi

keychain add-certificates
xcode-project use-profiles
echo "iOS signing hazır ($PROFILE_TYPE)"
