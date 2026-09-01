#!/usr/bin/env bash
# Codemagic iOS imza — CERTIFICATE_PRIVATE_KEY PEM ile cert + profil.
# 409 (cert limiti / eşleşmeyen eski cert) → tüm Distribution cert'leri iptal, yeniden oluştur.
set -euo pipefail

PROFILE_TYPE="${1:-IOS_APP_STORE}"
BUNDLE_ID="${BUNDLE_ID:-com.aystech.mtMobil}"

if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  echo "ERROR: CERTIFICATE_PRIVATE_KEY eksik (ios_code_signing grubu)."
  exit 1
fi

# PEM'i dosyaya yaz (@env bazen satır sonu kaybeder)
PEM_FILE="/tmp/codemagic_distribution_key.pem"
printf '%s\n' "$CERTIFICATE_PRIVATE_KEY" > "$PEM_FILE"
chmod 600 "$PEM_FILE"

keychain initialize

fetch_files() {
  local mode="${1:-fetch}"
  case "$mode" in
    create)
      app-store-connect fetch-signing-files "$BUNDLE_ID" \
        --type "$PROFILE_TYPE" \
        --certificate-key=@file:"$PEM_FILE" \
        --create
      ;;
    *)
      app-store-connect fetch-signing-files "$BUNDLE_ID" \
        --type "$PROFILE_TYPE" \
        --certificate-key=@file:"$PEM_FILE"
      ;;
  esac
}

list_distribution_cert_ids() {
  app-store-connect certificates list --type IOS_DISTRIBUTION --json 2>/dev/null \
    | python3 - <<'PY'
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
items = data if isinstance(data, list) else data.get("data", data.get("certificates", []))
for c in items:
    cid = c.get("id")
    if not cid and isinstance(c.get("attributes"), dict):
        cid = c["attributes"].get("id")
    if cid:
        name = (c.get("attributes") or {}).get("name") or c.get("name") or ""
        print(f"{cid}\t{name}")
PY
}

revoke_distribution_certs() {
  local only_expired="${1:-false}"
  echo "Distribution sertifikaları listeleniyor (only_expired=$only_expired)…"
  while IFS=$'\t' read -r cid name; do
    [ -z "$cid" ] && continue
    if [ "$only_expired" = "true" ]; then
      # Süresi dolmuş olanları python ile filtrele
      continue
    fi
    echo "Revoking IOS_DISTRIBUTION cert: $cid ${name:-}"
    app-store-connect certificates revoke --certificate-id "$cid" || true
  done < <(list_distribution_cert_ids)
}

revoke_expired_distribution() {
  app-store-connect certificates list --type IOS_DISTRIBUTION --json 2>/dev/null \
    | python3 - <<'PY'
import json, subprocess, sys
from datetime import datetime, timezone
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
items = data if isinstance(data, list) else data.get("data", data.get("certificates", []))
now = datetime.now(timezone.utc)
for c in items:
    attrs = c.get("attributes") or c
    cid = c.get("id") or attrs.get("id")
    exp = attrs.get("expirationDate") or c.get("expirationDate")
    if not cid or not exp:
        continue
    try:
        dt = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
    except ValueError:
        continue
    if dt < now:
        print(f"Revoking expired cert {cid}")
        subprocess.run(
            ["app-store-connect", "certificates", "revoke", "--certificate-id", str(cid)],
            check=False,
        )
PY
}

echo "iOS signing · bundle=$BUNDLE_ID · profile=$PROFILE_TYPE"

set +e
fetch_files fetch
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "Eşleşen cert yok (rc=$RC). Süresi dolmuş cert'ler temizleniyor…"
  revoke_expired_distribution
  set +e
  fetch_files create
  RC=$?
  set -e
fi

if [ "$RC" -ne 0 ]; then
  echo "WARN: --create başarısız (rc=$RC, muhtemelen 409). Tüm Distribution cert'ler iptal ediliyor…"
  revoke_distribution_certs false
  sleep 3
  set +e
  fetch_files create
  RC=$?
  set -e
fi

if [ "$RC" -ne 0 ]; then
  echo "ERROR: iOS imza dosyaları alınamadı (rc=$RC)."
  echo ""
  echo "Manuel adımlar:"
  echo "  1. developer.apple.com → Certificates → Apple Distribution sertifikalarını REVOKE et"
  echo "  2. Codemagic → ios_code_signing → CERTIFICATE_PRIVATE_KEY PEM'i doğrula"
  echo "  3. Build'i yeniden başlat"
  exit 1
fi

keychain add-certificates
xcode-project use-profiles
echo "iOS signing hazır ($PROFILE_TYPE)"
