#!/bin/bash
# Avisa cuando OVH vuelve a tener VPS-2 / VPS-3 con Linux en un centro de datos europeo.
#
# Consulta la API pública de OVH (sin cuenta ni claves):
#   https://eu.api.ovh.com/v1/vps/order/rule/datacenter?ovhSubsidiary=ES&planCode=<plan>
# y mira `linuxStatus`, no `status`: el 2026-10-30 el VPS-2 salía "available" en tres
# centros, pero sólo con Windows. Con Linux estaba agotado en todos.
#
# Sólo avisa del CAMBIO (agotado → disponible), no en cada pasada. Guarda lo que vio la
# última vez en $STATE_FILE; si algo se agota y vuelve, avisa otra vez.
#
# Configuración en config.env (ver config.env.example). Uso:
#   ./check-ovh-stock.sh            # comprueba y avisa
#   ./check-ovh-stock.sh --status   # sólo enseña la tabla actual, sin avisar ni guardar
#   ./check-ovh-stock.sh --test     # manda un aviso de prueba (para ver que llega al móvil)

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/config.env" ] && . "$DIR/config.env"

# Las 2027 son las que vende hoy la web de OVH España.
PLANS="${PLANS:-vps-2027-model2 vps-2027-model3}"
DATACENTERS="${DATACENTERS:-eu-west-gra eu-west-rbx eu-west-sbg eu-central-waw eu-west-lim eu-west-eri eu-south-mil}"
# El centro donde tengas (o vayas a tener) el VPS-1: la mejora sólo funciona dentro del mismo.
HOME_DC="${HOME_DC:-eu-west-gra}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
STATE_FILE="${STATE_FILE:-$DIR/.last-available}"
API="${OVH_API:-https://eu.api.ovh.com/v1}"

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

plan_name() {
  case "$1" in
    *model1*) echo "VPS-1" ;; *model2*) echo "VPS-2" ;; *model3*) echo "VPS-3" ;;
    *model4*) echo "VPS-4" ;; *) echo "$1" ;;
  esac
}

dc_name() {
  case "$1" in
    eu-west-gra) echo "Gravelines (FR)" ;; eu-west-rbx) echo "Roubaix (FR)" ;;
    eu-west-sbg) echo "Estrasburgo (FR)" ;; eu-central-waw) echo "Varsovia (PL)" ;;
    eu-west-lim) echo "Limburgo (DE)" ;; eu-west-eri) echo "Erith (UK)" ;;
    eu-south-mil) echo "Milán (IT)" ;; *) echo "$1" ;;
  esac
}

notify() {
  local title="$1" body="$2" priority="${3:-default}"
  log "AVISO: $title — $body"
  if [ -n "$NTFY_TOPIC" ]; then
    curl -fsS -m 20 -H "Title: $title" -H "Priority: $priority" -H "Tags: computer" \
      -H "Click: https://www.ovhcloud.com/es-es/vps/" \
      -d "$body" "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null || log "ntfy falló"
  fi
  # En el Mac, además, la notificación del sistema.
  if command -v osascript >/dev/null; then
    osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"Glass\"" 2>/dev/null
  fi
}

if [ "${1:-}" = "--test" ]; then
  [ -n "$NTFY_TOPIC" ] || { echo "Falta NTFY_TOPIC en config.env"; exit 1; }
  notify "Prueba del avisador de OVH" "Si lees esto en el móvil, los avisos de VPS te llegarán." high
  exit 0
fi

# Recoge "plan@centro" de todo lo disponible con Linux. Si la API falla, sale sin tocar
# el estado: un error de red no puede parecer un "se ha agotado".
available=""
for plan in $PLANS; do
  json="$(curl -fsS -m 20 "$API/vps/order/rule/datacenter?ovhSubsidiary=ES&planCode=$plan")" || {
    log "error consultando $plan; no se cambia nada"
    exit 1
  }
  for dc in $(printf '%s' "$json" | jq -r '.datacenters[] | select(.linuxStatus == "available") | .code'); do
    case " $DATACENTERS " in *" $dc "*) available="$available $plan@$dc" ;; esac
  done
done
available="$(printf '%s\n' $available | sed '/^$/d' | sort -u)"

if [ "${1:-}" = "--status" ]; then
  if [ -z "$available" ]; then echo "Nada disponible con Linux en: $DATACENTERS"; fi
  for item in $available; do echo "✅ $(plan_name "${item%@*}") — $(dc_name "${item#*@}")"; done
  exit 0
fi

previous="$(cat "$STATE_FILE" 2>/dev/null || true)"
new="$(comm -13 <(printf '%s\n' "$previous" | sed '/^$/d') <(printf '%s\n' "$available" | sed '/^$/d'))"

for item in $new; do
  plan="${item%@*}"; dc="${item#*@}"
  if [ "$dc" = "$HOME_DC" ]; then
    notify "¡$(plan_name "$plan") disponible en tu centro!" \
      "$(plan_name "$plan") con Linux en $(dc_name "$dc"). Puedes subir tu VPS desde el panel de OVH." high
  else
    notify "$(plan_name "$plan") disponible" \
      "$(plan_name "$plan") con Linux en $(dc_name "$dc"). Ojo: la mejora sólo funciona dentro del mismo centro."
  fi
done

printf '%s\n' "$available" > "$STATE_FILE"
log "comprobado: ${available:-nada disponible}" | tr '\n' ' '; echo
