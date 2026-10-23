#!/bin/bash
# Encode a 720p copy under 10 MB for GitHub README uploads (free accounts accept videos up to 10 MB).
# Film grain is removed first; it costs bitrate and is invisible at this size.
set -euo pipefail
cd "$(dirname "$0")/../out"
src="灵感晾台-介绍.mp4"
dst="灵感晾台-介绍-网页版.mp4"
log="$(mktemp -d)/x264"
vf="hqdn3d=2:1.5:3:3,scale=1280:720:flags=lanczos,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv"
ffmpeg -y -loglevel error -i "$src" -map 0:v:0 -an -vf "$vf" -c:v libx264 -preset slow -b:v 1750k -pass 1 -passlogfile "$log" -f mp4 /dev/null
ffmpeg -y -loglevel error -i "$src" -map 0:v:0 -map 0:a -vf "$vf" -c:v libx264 -preset slow -b:v 1750k -pass 2 -passlogfile "$log" \
  -profile:v high -colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a aac -b:a 96k -movflags +faststart "$dst"
ls -l "$dst"
