#!/usr/bin/env bash
set -Eeuo pipefail

# Instala Grafana Alloy en Magnus/Asterisk y configura el envío de
# logs de Asterisk y Heplify hacia Loki por Tailscale.
#
# Uso:
#   sudo LOKI_URL=http://100.100.2.64:3100 \
#     NODE_LABEL=magnus-erick \
#     bash install-alloy-magnus.sh
#
# El script no modifica Asterisk, Heplify ni HOMER.

if [[ ${EUID} -ne 0 ]]; then
  echo "Ejecuta este script como root (sudo)." >&2
  exit 1
fi

: "${LOKI_URL:=http://100.100.2.64:3100}"
: "${NODE_LABEL:=magnus-erick}"
: "${MAX_AGE:=24h}"
: "${APT_FRONTEND:=noninteractive}"

export DEBIAN_FRONTEND="$APT_FRONTEND"

apt-get update
apt-get install -y ca-certificates curl gnupg

install -d -m 0755 /etc/apt/keyrings
tmp_key="$(mktemp)"
trap 'rm -f "$tmp_key"' EXIT
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor > "$tmp_key"
install -m 0644 "$tmp_key" /etc/apt/keyrings/grafana.gpg

cat > /etc/apt/sources.list.d/grafana.list <<'EOF'
deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main
EOF

apt-get update
apt-get install -y alloy

# Alloy necesita leer el journal de systemd.
if getent group systemd-journal >/dev/null 2>&1; then
  /usr/sbin/usermod -aG systemd-journal alloy
fi

config=/etc/alloy/config.alloy
if [[ -f "$config" ]]; then
  backup="${config}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a "$config" "$backup"
  echo "Copia de seguridad: $backup"
fi

cat > "$config" <<EOF
logging {
  level = "warn"
}

loki.write "magnus" {
  endpoint {
    url = "${LOKI_URL}/loki/api/v1/push"
  }
}

loki.source.journal "asterisk" {
  matches = "_SYSTEMD_UNIT=asterisk.service"
  max_age = "${MAX_AGE}"

  labels = {
    job      = "asterisk",
    node     = "${NODE_LABEL}",
    servicio = "asterisk",
  }

  forward_to = [loki.write.magnus.receiver]
}

loki.source.journal "heplify" {
  matches = "_SYSTEMD_UNIT=heplify.service"
  max_age = "${MAX_AGE}"

  labels = {
    job      = "heplify",
    node     = "${NODE_LABEL}",
    servicio = "heplify",
  }

  forward_to = [loki.write.magnus.receiver]
}
EOF

alloy fmt --write "$config"
alloy validate "$config"

# Validación previa de red, sin enviar datos.
if command -v curl >/dev/null 2>&1; then
  curl --fail --silent --show-error --max-time 10 "${LOKI_URL}/ready" >/dev/null
fi

systemctl daemon-reload
systemctl enable --now alloy
systemctl --no-pager --full status alloy

echo
echo "Alloy quedó activo. Verifica los streams con:"
echo "  curl -G -sS --data-urlencode 'query={job="asterisk"}' --data-urlencode 'limit=5' \\"
echo "    ${LOKI_URL}/loki/api/v1/query_range"
echo "  curl -G -sS --data-urlencode 'query={job="heplify"}' --data-urlencode 'limit=5' \\"
echo "    ${LOKI_URL}/loki/api/v1/query_range"
