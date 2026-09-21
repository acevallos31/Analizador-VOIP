#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${TRUNK_MONITOR_CONFIG:-/etc/trunk-monitor/config.env}"
STATE_DIR="${TRUNK_MONITOR_STATE_DIR:-/var/lib/trunk-monitor}"
LOGGER_TAG="${TRUNK_MONITOR_LOGGER_TAG:-trunk-monitor}"

if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "No existe la configuración: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${TRUNKS:?TRUNKS no está definido en $CONFIG_FILE}"
: "${ASTERISK_BIN:=/usr/sbin/asterisk}"

install -d -m 0750 "$STATE_DIR"
output="$(timeout "${ASTERISK_TIMEOUT_SECONDS:-15}" "$ASTERISK_BIN" -rx "sip show peers" 2>&1)" || {
  logger -t "$LOGGER_TAG" -p daemon.err -- "monitor_error=asterisk_cli_failed"
  exit 1
}

run_status="ok"
changed=0

for trunk in $TRUNKS; do
  line="$(awk -v p="$trunk" '
    $1 == p || $1 ~ ("^" p "/") { print; exit }
  ' <<< "$output")"

  if [[ -z "$line" ]]; then
    status="MISSING"
    detail="peer_not_found"
    run_status="degraded"
  else
    status="$(grep -oE 'UNREACHABLE|UNKNOWN|LAGGED|UNMONITORED|OK' <<< "$line" | head -n1 || true)"
    status="${status:-UNKNOWN}"
    detail="$(tr -s '[:space:]' ' ' <<< "$line" | cut -c1-240)"
    [[ "$status" == "OK" ]] || run_status="degraded"
  fi

  state_file="$STATE_DIR/$trunk.state"
  previous=""
  [[ -r "$state_file" ]] && previous="$(<"$state_file")"

  if [[ "$status" != "$previous" ]]; then
    printf '%s\n' "$status" > "$state_file"
    logger -t "$LOGGER_TAG" -p daemon.warning -- \
      "event=trunk_state_change trunk=$trunk status=$status previous=${previous:-INITIAL} detail=$detail"
    changed=1
  fi
done

logger -t "$LOGGER_TAG" -p daemon.info -- \
  "event=monitor_run status=$run_status changed=$changed trunks=$(wc -w <<< "$TRUNKS")"

exit 0
