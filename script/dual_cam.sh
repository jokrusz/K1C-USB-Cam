#!/bin/sh

pkill -9 mjpg_streamer 2>/dev/null

fuser -k /dev/video4 2>/dev/null
fuser -k /dev/video5 2>/dev/null

CAM1=$(v4l2-ctl --list-devices | awk '/^CCX2F3298 .*usb-/{f=1; next} f && /\/dev\/video[0-9]+/{print $1; exit}')
CAM2=$(v4l2-ctl --list-devices | awk '/^CCX2F3299 .*usb-/{f=1; next} f && /\/dev\/video[0-9]+/{print $1; exit}')

echo "CAM1=$CAM1"
echo "CAM2=$CAM2"

mjpg_streamer -b \
  -i "/usr/lib/mjpg-streamer/input_uvc.so -d $CAM1 -n cam1" \
  -i "/usr/lib/mjpg-streamer/input_uvc.so -d $CAM2 -n cam2" \
  -o "/usr/lib/mjpg-streamer/output_http.so -p 8080"
