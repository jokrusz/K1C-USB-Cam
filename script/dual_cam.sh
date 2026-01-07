#!/bin/sh

MJPG_BIN="${MJPG_BIN:-mjpg_streamer}"
INPUT_PLUGIN="${INPUT_PLUGIN:-/usr/lib/mjpg-streamer/input_uvc.so}"
OUTPUT_PLUGIN="${OUTPUT_PLUGIN:-/usr/lib/mjpg-streamer/output_http.so}"
PORT_DEFAULT="${PORT_DEFAULT:-8080}"

TMP="/tmp/mjpg_usb.$$"
trap 'rm -f "$TMP"' EXIT

need() {
  command -v "$1" >/dev/null 2>&1 || { printf "Fehlt: %s\n" "$1" > /dev/tty; exit 1; }
}

need sed
need pidof

command -v "$MJPG_BIN" >/dev/null 2>&1 || { printf "mjpg_streamer nicht gefunden\n" > /dev/tty; exit 1; }

kill_mjpg_streamer() {
  PIDS="$(pidof mjpg_streamer 2>/dev/null)"
  if [ -n "$PIDS" ]; then
    kill -9 $PIDS 2>/dev/null || true
  fi
}

kill_users_of_cam() {
  CAM="$1"
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "$CAM" 2>/dev/null || true
  fi
}

port_listening() {
  PORT="$1"
  HEXPORT=$(printf '%04X' "$PORT" | tr '[:lower:]' '[:upper:]')

  if [ -r /proc/net/tcp ]; then
    if awk -v hp=":$HEXPORT" '
      NR>1 {
        local=$2
        state=$4
        if (local ~ hp"$" && state=="0A") { found=1; exit }
      }
      END { exit(found?0:1) }
    ' /proc/net/tcp; then
      return 0
    fi
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -lnt 2>/dev/null | grep -q ":$PORT " && return 0
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -q ":$PORT " && return 0
  fi

  return 2
}

pick_line() {
  file="$1"
  prompt="$2"
  while :; do
    printf "%s\n> " "$prompt" > /dev/tty
    read -r n < /dev/tty
    case "$n" in
      ''|*[!0-9]*)
        printf "Bitte eine Zahl eingeben\n" > /dev/tty
        continue
        ;;
    esac
    line=$(sed -n "${n}p" "$file")
    [ -n "$line" ] || { printf "Ungültige Auswahl\n" > /dev/tty; continue; }
    echo "$line"
    return 0
  done
}

USB1="/dev/video4"
USB2="/dev/video5"

BY_PATH_4="/dev/v4l/by-path/platform-13500000.otg_new-usb-0:1.3:1.0-video-index0"
if [ -e "$BY_PATH_4" ]; then
  USB1="$BY_PATH_4"
fi

rm -f "$TMP"
if [ -e "$USB1" ]; then
  printf "usb cam a|%s\n" "$USB1" >> "$TMP"
fi
if [ -e "$USB2" ]; then
  printf "usb cam b|%s\n" "$USB2" >> "$TMP"
fi

if [ ! -s "$TMP" ]; then
  printf "Keine USB Kameras gefunden\n" > /dev/tty
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

SEL1=$(pick_line "$TMP" "Welche Kamera soll Stream 1 sein Nummer")
SEL2=$(pick_line "$TMP" "Welche Kamera soll Stream 2 sein Nummer")

CAM1=$(echo "$SEL1" | sed 's/.*|//')
CAM2=$(echo "$SEL2" | sed 's/.*|//')

if [ "$CAM1" = "$CAM2" ]; then
  printf "Du hast zweimal das gleiche Device gewählt\n" > /dev/tty
  exit 1
fi

printf "Port für HTTP Server [%s]\n> " "$PORT_DEFAULT" > /dev/tty
read -r PORT < /dev/tty
[ -n "$PORT" ] || PORT="$PORT_DEFAULT"

kill_mjpg_streamer
kill_users_of_cam "$CAM1"
kill_users_of_cam "$CAM2"

printf "Starte mjpg_streamer\n" > /dev/tty
"$MJPG_BIN" -b \
  -i "$INPUT_PLUGIN -d $CAM1 -n cam1" \
  -i "$INPUT_PLUGIN -d $CAM2 -n cam2" \
  -o "$OUTPUT_PLUGIN -p $PORT"

sleep 1

PIDS_AFTER="$(pidof mjpg_streamer 2>/dev/null)"
if [ -z "$PIDS_AFTER" ]; then
  printf "Start fehlgeschlagen mjpg_streamer läuft nicht\n" > /dev/tty
  exit 1
fi

port_listening "$PORT"
PORT_RC=$?
if [ "$PORT_RC" -eq 1 ]; then
  printf "mjpg_streamer läuft aber Port %s ist nicht im Listen Status\n" "$PORT" > /dev/tty
  exit 1
fi
if [ "$PORT_RC" -eq 2 ]; then
  printf "mjpg_streamer läuft Port Prüfung nicht möglich ss oder netstat fehlen\n" > /dev/tty
fi

printf "\nGestartet PID %s\n" "$PIDS_AFTER" > /dev/tty
printf "Zugriff\n" > /dev/tty
printf "  http://IP:%s/?action=stream\n" "$PORT" > /dev/tty
printf "  http://IP:%s/?action=stream_1\n" "$PORT" > /dev/tty
