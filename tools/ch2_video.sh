#!/bin/bash
# ch2_video.sh FRAMES_DIR OUT.mp4 [fps=30] [sub=4]: averages each group of `sub` sub-frames (tools/ch2_render.gd) into one frame (motion blur), encodes H.264.
D=${1:-/c/Temp/claude/ch2_frames}; O=${2:-out/ch2/clock.mp4}; FPS=${3:-30}; SUB=${4:-4}
FF=/c/Users/Nick/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.2-full_build/bin/ffmpeg
mkdir -p "$(dirname "$O")"
"$FF" -y -framerate $((FPS * SUB)) -i "$D/f%05d.png" -vf "tmix=frames=${SUB},select='eq(mod(n\,${SUB})\,$((SUB - 1)))',setpts=N/(${FPS}*TB)" -r $FPS -c:v libx264 -pix_fmt yuv420p -crf 18 "$O"
