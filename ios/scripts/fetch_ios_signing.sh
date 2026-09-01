#!/usr/bin/env bash
# Codemagic iOS imza — eski Distribution cert sil → yeni key + cert + profil.
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

delete_certs_from_json() {
  local json_file="$1"
  local label="$2"
  if [ ! -s "$json_file" ]; then
    echo "  $label: liste boş"
    return 0
  fi
  python3 - "$json_file" "$label" <<'PY'
import json, subprocess, sys
path, label = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception as e:
    print(f"  {label}: JSON okunamadı ({e})")
    sys.exit(0)
items = data if isinstance(data, list) else data.get("data", data.get("certificates", []))
if not items:
    print(f"  {label}: 0 sertifika")
    sys.exit(0)
deleted = 0
for c in items:
    cid = c.get("id")
    attrs = c.get("attributes") or {}
    ctype = attrs.get("certificateType") or attrs.get("name") or "?"
    if not cid:
        continue
    print(f"  Delete {ctype} · id={cid}")
    r = subprocess.run(
        ["app-store-connect", "certificates", "delete", str(cid), "--ignore-not-found"],
        capture_output=True,
        text=True,
    )
    if r.returncode == 0:
        deleted += 1
    else:
        err = (r.stderr or r.stdout or "").strip()
        print(f"    WARN rc={r.returncode} {err[:200]}")
print(f"  {label}: {deleted}/{len(items)} silindi")
PY
}

delete_all_distribution() {
  echo "Distribution sertifikaları siliniyor…"
  for cert_type in IOS_DISTRIBUTION DISTRIBUTION; do
    local out="/tmp/certs_${cert_type}.json"
    set +e
    app-store-connect certificates list --type "$cert_type" --json > "$out" 2>/tmp/cert_list_err.txt
    local rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      echo "  WARN list --type $cert_type rc=$rc"
      cat /tmp/cert_list_err.txt 2>/dev/null | head -3 || true
      continue
    fi
    delete_certs_from_json "$out" "$cert_type"
  done

  # Tip filtresi kaçırırsa: tüm listeyi tara
  set +e
  app-store-connect certificates list --json > /tmp/certs_all.json 2>/dev/null
  set -e
  if [ -s /tmp/certs_all.json ]; then
    python3 - /tmp/certs_all.json <<'PY'
import json, subprocess, sys
data = json.load(open(sys.argv[1]))
items = data if isinstance(data, list) else data.get("data", [])
dist = {"IOS_DISTRIBUTION", "DISTRIBUTION", "APPLE_DISTRIBUTION"}
for c in items:
    attrs = c.get("attributes") or {}
    ctype = attrs.get("certificateType", "")
    cid = c.get("id")
    if cid and ctype in dist:
        print(f"  Delete (all) {ctype} · id={cid}")
        subprocess.run(
            ["app-store-connect", "certificates", "delete", str(cid), "--ignore-not-found"],
            check=False,
        )
PY
  fi
}

create_signing() {
  local args=(fetch-signing-files "$BUNDLE_ID" --type "$PROFILE_TYPE" --create)
  args+=(--certificate-key="@file:${PEM_FILE}")
  echo "app-store-connect ${args[*]}"
  app-store-connect "${args[@]}"
}

if prepare_pem_file; then
  USE_PEM=1
  echo "Private key PEM bulundu ($(wc -c < "$PEM_FILE" | tr -d ' ') byte)"
else
  echo "PEM yok — yeni RSA private key üretiliyor (openssl)…"
  openssl genrsa -out "$PEM_FILE" 2048
  chmod 600 "$PEM_FILE"
  USE_PEM=1
  if [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
    echo "  WARN: CERTIFICATE_PRIVATE_KEY geçersiz, yeni key kullanılıyor."
  fi
fi

keychain initialize

echo "iOS signing · bundle=$BUNDLE_ID · profile=$PROFILE_TYPE · pem=$USE_PEM"

delete_all_distribution
echo "Apple API cert silme sonrası bekleniyor…"
sleep 5

set +e
create_signing
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "İlk --create başarısız (rc=$RC). Cert'ler tekrar silinip deneniyor…"
  delete_all_distribution
  sleep 8
  set +e
  create_signing
  RC=$?
  set -e
fi

if [ "$RC" -ne 0 ]; then
  echo "ERROR: iOS imza oluşturulamadı (rc=$RC)."
  echo ""
  echo "Manuel (1 dk): developer.apple.com → Certificates"
  echo "  → Apple Distribution / iOS Distribution → hepsini DELETE"
  echo "  → Pending certificate request varsa iptal et"
  echo "Sonra build'i yeniden başlat."
  exit 1
fi

keychain add-certificates
xcode-project use-profiles

echo "Profil dosyaları:"
find "$HOME/Library/MobileDevice/Provisioning Profiles" -name "*.mobileprovision" 2>/dev/null | head -5 || true

echo "iOS signing hazır ($PROFILE_TYPE)"
