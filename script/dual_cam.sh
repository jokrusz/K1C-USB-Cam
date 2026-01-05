#!/usr/bin/env sh
set -euo pipefail

MJPG_BIN="${MJPG_BIN:-mjpg_streamer}"
INPUT_PLUGIN="${INPUT_PLUGIN:-/usr/lib/mjpg-streamer/input_uvc.so}"
OUTPUT_PLUGIN="${OUTPUT_PLUGIN:-/usr/lib/mjpg-streamer/output_http.so}"
PORT_DEFAULT="${PORT_DEFAULT:-8080}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1"; exit 1; }; }
need v4l2-ctl
need awk
need sed

if ! command -v "$MJPG_BIN" >/dev/null 2>&1; then
  echo "mjpg_streamer nicht gefunden: $MJPG_BIN"
  exit 1
fi

mapfile -t CAMS < <(
  v4l2-ctl --list-devices | awk '
    /^[^[:space:]].*\):$/ { dev=$0; sub(/\):$/,"",dev); next }
    /^[[:space:]]+\/dev\/video[0-9]+/ {
      v=$1
      if (dev != "") print dev "|" v
    }
  ' | sed '/v4l2loopback/d'
)

if ((${#CAMS[@]} == 0)); then
  echo "Keine Kameras gefunden"
  exit 1
fi

echo
echo "Gefundene Video Devices"
for i in "${!CAMS[@]}"; do
  name="${CAMS[$i]%%|*}"
  node="${CAMS[$i]##*|}"
  printf "  %2d) %s  %s\n" "$((i+1))" "$node" "$name"
done
echo

choose_cam() {
  local prompt="$1"
  local choice=""
  while true; do
    read -r -p "$prompt " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Bitte eine Zahl eingeben"; continue; }
    (( choice >= 1 && choice <= ${#CAMS[@]} )) || { echo "Ungültige Auswahl"; continue; }
    echo "${CAMS[$((choice-1))]}"
    return 0
  done
}

SEL1="$(choose_cam "Welche Kamera soll Stream 1 sein Nummer")"
SEL2="$(choose_cam "Welche Kamera soll Stream 2 sein Nummer")"

CAM1="${SEL1##*|}"
CAM2="${SEL2##*|}"
NAME1="${SEL1%%|*}"
NAME2="${SEL2%%|*}"

if [[ "$CAM1" == "$CAM2" ]]; then
  echo "Du hast zweimal das gleiche Device gewählt"
  exit 1
fi

read -r -p "Port für HTTP Server [${PORT_DEFAULT}] " PORT
PORT="${PORT:-$PORT_DEFAULT}"

echo
echo "Auswahl"
echo "  Stream 1: $CAM1  $NAME1"
echo "  Stream 2: $CAM2  $NAME2"
echo "  Port:     $PORT"
echo

read -r -p "Laufenden mjpg_streamer beenden ja nein [ja] " ANS
ANS="${ANS:-ja}"
if [[ "$ANS" == "ja" || "$ANS" == "j" || "$ANS" == "y" ]]; then
  pkill -9 mjpg_streamer 2>/dev/null || true
fi

read -r -p "Prozesse beenden die die Devices nutzen ja nein [nein] " KILLFUSER
KILLFUSER="${KILLFUSER:-nein}"
if [[ "$KILLFUSER" == "ja" || "$KILLFUSER" == "j" || "$KILLFUSER" == "y" ]]; then
  fuser -k "$CAM1" 2>/dev/null || true
  fuser -k "$CAM2" 2>/dev/null || true
fi

echo
echo "Starte mjpg_streamer"
"$MJPG_BIN" -b \
  -i "$INPUT_PLUGIN -d $CAM1 -n cam1" \
  -i "$INPUT_PLUGIN -d $CAM2 -n cam2" \
  -o "$OUTPUT_PLUGIN -p $PORT"

echo
echo "Zugriff meist so"
echo "  http://IP:$PORT/?action=stream&stream=cam1"
echo "  http://IP:$PORT/?action=stream&stream=cam2"
