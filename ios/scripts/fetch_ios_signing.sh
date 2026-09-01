#!/usr/bin/env bash
# Codemagic iOS imza: önce mevcut cert/profil, gerekirse --create.
# 409 "already have a Distribution certificate" → süresi dolmuş cert'leri sil, tekrar dene.
set -euo pipefail

PROFILE_TYPE="${1:-IOS_APP_STORE}"
BUNDLE_ID="${BUNDLE_ID:-com.aystech.mtMobil}"

if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  echo "ERROR: CERTIFICATE_PRIVATE_KEY eksik (ios_code_signing grubu)."
  exit 1
fi

keychain initialize

fetch_files() {
  local extra="${1:-}"
  if [ "$extra" = "--create" ]; then
    app-store-connect fetch-signing-files "$BUNDLE_ID" \
      --type "$PROFILE_TYPE" \
      --certificate-key=@env:CERTIFICATE_PRIVATE_KEY \
      --create
  else
    app-store-connect fetch-signing-files "$BUNDLE_ID" \
      --type "$PROFILE_TYPE" \
      --certificate-key=@env:CERTIFICATE_PRIVATE_KEY
  fi
}

revoke_expired_distribution() {
  echo "Süresi dolmuş IOS_DISTRIBUTION sertifikaları kontrol ediliyor…"
  set +e
  app-store-connect certificates list --type IOS_DISTRIBUTION --json > /tmp/dist_certs.json 2>/dev/null
  if [ -s /tmp/dist_certs.json ]; then
    python3 - <<'PY'
import json, subprocess
from datetime import datetime, timezone
try:
    data = json.load(open("/tmp/dist_certs.json"))
except Exception:
    data = []
items = data if isinstance(data, list) else data.get("data", data.get("certificates", []))
now = datetime.now(timezone.utc)
for c in items:
    attrs = c.get("attributes", c)
    cid = c.get("id") or attrs.get("id")
    exp = attrs.get("expirationDate") or c.get("expirationDate")
    if not cid or not exp:
        continue
    try:
        dt = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
    except ValueError:
        continue
    if dt < now:
        print(f"Revoking expired cert {cid} ({exp})")
        subprocess.run(
            ["app-store-connect", "certificates", "revoke", "--certificate-id", str(cid)],
            check=False,
        )
PY
  fi
  set -e
}

echo "iOS signing · bundle=$BUNDLE_ID · profile=$PROFILE_TYPE"

set +e
fetch_files
RC=$?
set -e

if [ "$RC" -eq 0 ]; then
  echo "Mevcut imza dosyaları kullanıldı."
else
  echo "Eşleşen cert yok (rc=$RC). Süresi dolmuş cert'ler temizleniyor, --create deneniyor…"
  revoke_expired_distribution
  set +e
  fetch_files --create
  RC=$?
  set -e
  if [ "$RC" -ne 0 ]; then
    echo "WARN: --create başarısız (rc=$RC). Profil-only fetch deneniyor…"
    set +e
    app-store-connect fetch-signing-files "$BUNDLE_ID" --type "$PROFILE_TYPE"
    RC=$?
    set -e
    if [ "$RC" -ne 0 ]; then
      echo "ERROR: iOS imza dosyaları alınamadı."
      echo "Apple Developer → Certificates → eski Distribution sertifikalarından birini iptal edin"
      echo "veya CERTIFICATE_PRIVATE_KEY PEM'inin mevcut cert ile eşleştiğinden emin olun."
      exit 1
    fi
  fi
fi

keychain add-certificates
xcode-project use-profiles
echo "iOS signing hazır ($PROFILE_TYPE)"
