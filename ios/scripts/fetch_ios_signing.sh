#!/usr/bin/env bash
# Codemagic iOS imza — cert + provisioning profile --create ile üretilir.
# ios_signing YAML bloğu KULLANMA (hazır profil arar → "No matching profiles" hatası).
set -uo pipefail

PROFILE_TYPE="${1:-IOS_APP_STORE}"
BUNDLE_ID="${BUNDLE_ID:-com.aystech.mtMobil}"
PEM_FILE="/tmp/codemagic_distribution_key.pem"
USE_PEM=0

echo "iOS signing script · commit=$(git rev-parse --short HEAD 2>/dev/null || echo '?')"

pem_looks_valid() {
  grep -qE 'BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY' "$1" 2>/dev/null
}

prepare_pem_file() {
  : > "$PEM_FILE"

  if [ -f "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
    cp "${CERTIFICATE_PRIVATE_KEY}" "$PEM_FILE"
    chmod 600 "$PEM_FILE"
    pem_looks_valid "$PEM_FILE" && return 0
  fi

  if [ -n "${CERTIFICATE_PRIVATE_KEY_BASE64:-}" ]; then
    echo "$CERTIFICATE_PRIVATE_KEY_BASE64" | tr -d '[:space:]' | base64 --decode > "$PEM_FILE" 2>/dev/null || true
    chmod 600 "$PEM_FILE"
    pem_looks_valid "$PEM_FILE" && return 0
  fi

  if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
    return 1
  fi

  local raw="$CERTIFICATE_PRIVATE_KEY"
  raw="${raw#\"}"; raw="${raw%\"}"
  raw="${raw#\'}"; raw="${raw%\'}"

  printf '%b' "$raw" > "$PEM_FILE"
  chmod 600 "$PEM_FILE"
  pem_looks_valid "$PEM_FILE" && return 0

  printf '%s' "$raw" | sed 's/\\n/\n/g' > "$PEM_FILE"
  pem_looks_valid "$PEM_FILE" && return 0

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

delete_all_distribution() {
  echo "Mevcut IOS_DISTRIBUTION sertifikaları siliniyor…"
  set +e
  app-store-connect certificates list --type IOS_DISTRIBUTION --json > /tmp/dist_certs.json
  LIST_RC=$?
  set -e
  if [ "$LIST_RC" -ne 0 ] || [ ! -s /tmp/dist_certs.json ]; then
    echo "WARN: cert listesi alınamadı (rc=$LIST_RC)"
    return 0
  fi
  python3 /dev/stdin /tmp/dist_certs.json <<'PY'
import json, subprocess, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
items = data if isinstance(data, list) else data.get("data", data.get("certificates", []))
for c in items:
    cid = c.get("id") or (c.get("attributes") or {}).get("id")
    if not cid:
        continue
    print(f"Delete cert {cid}")
    subprocess.run(
        ["app-store-connect", "certificates", "delete", str(cid), "--ignore-not-found"],
        check=False,
    )
PY
}

create_signing() {
  local args=(fetch-signing-files "$BUNDLE_ID" --type "$PROFILE_TYPE" --create)
  if [ "$USE_PEM" -eq 1 ]; then
    args+=(--certificate-key="@file:${PEM_FILE}")
  fi
  echo "app-store-connect ${args[*]}"
  app-store-connect "${args[@]}"
}

if prepare_pem_file; then
  USE_PEM=1
  echo "Private key PEM bulundu ($(wc -c < "$PEM_FILE" | tr -d ' ') byte)"
else
  echo "PEM yok — API yeni Distribution cert + profil oluşturacak."
  if [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
    echo "  WARN: CERTIFICATE_PRIVATE_KEY geçersiz, yok sayılıyor."
  fi
fi

keychain initialize

echo "iOS signing · bundle=$BUNDLE_ID · profile=$PROFILE_TYPE · pem=$USE_PEM"

# 409 önlemek: eski Distribution cert'leri sil, sonra yenisini oluştur
delete_all_distribution
sleep 2

set +e
create_signing
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "İlk --create başarısız (rc=$RC). Cert'ler tekrar silinip deneniyor…"
  delete_all_distribution
  sleep 3
  set +e
  create_signing
  RC=$?
  set -e
fi

if [ "$RC" -ne 0 ]; then
  echo "ERROR: iOS imza oluşturulamadı (rc=$RC)."
  echo "Kontrol:"
  echo "  • App Store Connect → Identifiers → $BUNDLE_ID kayıtlı mı?"
  echo "  • Codemagic integration AYSCODEMAGIC → Admin rolü"
  echo "  • developer.apple.com → Certificates → eski Distribution delete"
  exit 1
fi

keychain add-certificates
xcode-project use-profiles

echo "Profil dosyaları:"
find "$HOME/Library/MobileDevice/Provisioning Profiles" -name "*.mobileprovision" 2>/dev/null | head -5 || true
ls -la ~/export_options.plist 2>/dev/null || true

echo "iOS signing hazır ($PROFILE_TYPE)"
