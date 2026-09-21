#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Ejecuta como root." >&2
  exit 1
fi

repo_dir="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
config_dir=/etc/trunk-monitor
config_file="$config_dir/config.env"

install -d -m 0750 "$config_dir" /var/lib/trunk-monitor
install -m 0750 "$repo_dir/scripts/check-magnus-trunks.sh" /usr/local/sbin/check-magnus-trunks.sh

if [[ ! -e "$config_file" ]]; then
  install -m 0640 "$repo_dir/config/trunk-monitor.example.env" "$config_file"
  echo "Configuración creada en $config_file; revísala antes de continuar."
else
  echo "Se conserva la configuración existente: $config_file"
fi

install -m 0644 "$repo_dir/systemd/trunk-monitor.service" /etc/systemd/system/trunk-monitor.service
install -m 0644 "$repo_dir/systemd/trunk-monitor.timer" /etc/systemd/system/trunk-monitor.timer

systemctl daemon-reload
systemctl enable --now trunk-monitor.timer
systemctl start trunk-monitor.service

systemctl --no-pager --full status trunk-monitor.timer
echo
echo "Últimos eventos:"
journalctl -u trunk-monitor.service -n 20 --no-pager
