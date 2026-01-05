#!/bin/sh

MJPG_BIN="${MJPG_BIN:-mjpg_streamer}"
INPUT_PLUGIN="${INPUT_PLUGIN:-/usr/lib/mjpg-streamer/input_uvc.so}"
OUTPUT_PLUGIN="${OUTPUT_PLUGIN:-/usr/lib/mjpg-streamer/output_http.so}"
PORT_DEFAULT="${PORT_DEFAULT:-8080}"

TMP="/tmp/mjpg_cams.$$"
trap 'rm -f "$TMP"' EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1" > /dev/tty; exit 1; }
}

need v4l2-ctl
need awk
need sed

command -v "$MJPG_BIN" >/dev/null 2>&1 || { echo "mjpg_streamer nicht gefunden: $MJPG_BIN" > /dev/tty; exit 1; }

v4l2-ctl --list-devices | awk '
  /^[^[:space:]].*\):$/ {
    dev=$0
    sub(/\):$/,"",dev)
    next
  }
  /^[[:space:]]+\/dev\/video[0-9]+/ {
    node=$1
    if (dev != "") print dev "|" node
  }
' | sed -n '/usb-/p' | sed '/v4l2loopback/d' > "$TMP"

if [ ! -s "$TMP" ]; then
  echo "Keine USB Kameras gefunden" > /dev/tty
  exit 1
fi

printf "\nGefundene USB Kameras\n" > /dev/tty
i=1
while IFS= read -r line; do
  name=$(echo "$line" | sed 's/|.*//')
  node=$(echo "$line" | sed 's/.*|//')
  printf "  %2d) %s  %s\n" "$i" "$node" "$name" > /dev/tty
  i=$((i+1))
done < "$TMP"
printf "\n" > /dev/tty

pick_line() {
  prompt="$1"
  while :; do
    printf "%s\n> " "$prompt" > /dev/tty
    read -r choice < /dev/tty

    case "$choice" in
      ''|*[!0-9]*)
        printf "Bitte eine Zahl eingeben\n" > /dev/tty
        continue
        ;;
    esac

    line=$(sed -n "${choice}p" "$TMP")
    if [ -z "$line" ]; then
      printf "Ungültige Auswahl\n" > /dev/tty
      continue
    fi

    echo "$line"
    return 0
  done
}

SEL1=$(pick_line "Welche USB Kamera soll Stream 1 sein Nummer")
SEL2=$(pick_line "Welche USB Kamera soll Stream 2 sein Nummer")

CAM1=$(echo "$SEL1" | sed 's/.*|//')
CAM2=$(echo "$SEL2" | sed 's/.*|//')
NAME1=$(echo "$SEL1" | sed 's/|.*//')
NAME2=$(echo "$SEL2" | sed 's/|.*//')

if [ "$CAM1" = "$CAM2" ]; then
  echo "Du hast zweimal das gleiche Device gewählt" > /dev/tty
  exit 1
fi

printf "Port für HTTP Server [%s]\n> " "$PORT_DEFAULT" > /dev/tty
read -r PORT < /dev/tty
[ -n "$PORT" ] || PORT="$PORT_DEFAULT"

printf "\nAuswahl\n" > /dev/tty
printf "  Stream 1: %s  %s\n" "$CAM1" "$NAME1" > /dev/tty
printf "  Stream 2: %s  %s\n" "$CAM2" "$NAME2" > /dev/tty
printf "  Port:     %s\n\n" "$PORT" > /dev/tty

printf "Laufenden mjpg_streamer beenden ja nein [ja]\n> " > /dev/tty
read -r ANS < /dev/tty
[ -n "$ANS" ] || ANS="ja"
case "$ANS" in
  ja|j|y|Y)
    pkill -9 mjpg_streamer 2>/dev/null || true
    ;;
esac

printf "Prozesse beenden die die Devices nutzen ja nein [nein]\n> " > /dev/tty
read -r KILLFUSER < /dev/tty
[ -n "$KILLFUSER" ] || KILLFUSER="nein"
case "$KILLFUSER" in
  ja|j|y|Y)
    fuser -k "$CAM1" 2>/dev/null || true
    fuser -k "$CAM2" 2>/dev/null || true
    ;;
esac

echo "Starte mjpg_streamer" > /dev/tty
"$MJPG_BIN" -b \
  -i "$INPUT_PLUGIN -d $CAM1 -n cam1" \
  -i "$INPUT_PLUGIN -d $CAM2 -n cam2" \
  -o "$OUTPUT_PLUGIN -p $PORT"

printf "\nZugriff\n" > /dev/tty
printf "  http://IP:%s/?action=stream\n" "$PORT" > /dev/tty
printf "  http://IP:%s/?action=stream_1\n" "$PORT" > /dev/tty
