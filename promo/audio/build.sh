#!/bin/sh
# Builds video/assets/audio/mix.wav: synthesized music + sound effects, normalised to about -14 LUFS.
set -e
cd "$(dirname "$0")"
mkdir -p build ../video/assets/audio
python3 -I synth.py build 0.8 0.45
PRE="[0:a][1:a]amix=inputs=2:normalize=0:duration=longest"
M=$(ffmpeg -hide_banner -i build/music.wav -i build/sfx.wav -filter_complex "$PRE,loudnorm=I=-14:TP=-1.5:LRA=11:print_format=summary" -f null - 2>&1)
II=$(echo "$M" | awk '/Input Integrated/{print $3}'); TP=$(echo "$M" | awk '/Input True Peak/{print $4}')
LR=$(echo "$M" | awk '/Input LRA:/{print $3}'); TH=$(echo "$M" | awk '/Input Threshold/{print $3}'); OF=$(echo "$M" | awk '/Target Offset/{print $3}')
ffmpeg -hide_banner -loglevel error -y -i build/music.wav -i build/sfx.wav -filter_complex "$PRE,loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$II:measured_TP=$TP:measured_LRA=$LR:measured_thresh=$TH:offset=$OF:linear=true,aresample=48000" -c:a pcm_s16le ../video/assets/audio/mix.wav
