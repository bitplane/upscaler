#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:?usage: ./upscale.sh input.mp4 output.mp4}"
OUTPUT="${2:?usage: ./upscale.sh input.mp4 output.mp4}"

BASENAME="$(basename "$INPUT")"
WORKDIR="./work/${BASENAME}"
FRAMES="${WORKDIR}/frames"
DEBLOCKED="${WORKDIR}/deblocked"
UPSCALED="${WORKDIR}/upscaled"
LOGFILE="${WORKDIR}/process.log"
BINDIR="./bin"

mkdir -p "$FRAMES" "$DEBLOCKED" "$UPSCALED" "$BINDIR"
exec > >(tee -a "$LOGFILE") 2>&1

echo "== $(date) Starting pipeline for $INPUT =="

# --- ensure deps ---
if ! command -v ffmpeg >/dev/null; then
  echo "Installing ffmpeg..."
  sudo apt update && sudo apt install -y ffmpeg
fi

REALESRGAN="${BINDIR}/realesrgan-ncnn-vulkan"
if [ ! -x "$REALESRGAN" ]; then
  echo "Building Real-ESRGAN from source..."
  echo "NOTE: Requires git, cmake, build-essential, libvulkan1, vulkan-tools, libopencv-dev"
  echo "      Please install with: sudo apt update && sudo apt install -y git cmake build-essential libvulkan1 vulkan-tools libopencv-dev"

  cd "$BINDIR"
  rm -rf Real-ESRGAN-ncnn-vulkan

  git clone --depth=1 https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan.git
  cd Real-ESRGAN-ncnn-vulkan
  git submodule update --init --recursive
  cd src
  mkdir -p build && cd build
  cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 ..
  make -j"$(nproc)"
  cp realesrgan-ncnn-vulkan ../../../realesrgan-ncnn-vulkan
  cd ../../../
  chmod +x realesrgan-ncnn-vulkan
  cd - >/dev/null
fi

# --- step 1: extract frames ---
echo "🎞️ Extracting frames..."
ffmpeg -y -i "$INPUT" -qscale:v 2 "$FRAMES/frame_%08d.png"

# --- step 2: deblock ---
echo "🧽 Deblocking..."
ffmpeg -y -i "$FRAMES/frame_%08d.png" -vf deblock "$DEBLOCKED/frame_%08d.png"

# --- step 3: upscale ---
echo "🚀 Upscaling..."
"$REALESRGAN" -i "$DEBLOCKED/" -o "$UPSCALED/" -n realesrgan-x2plus

# --- step 4: reassemble ---
echo "🎬 Reassembling..."
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$INPUT")
ffmpeg -y -framerate "$FPS" -i "$UPSCALED/frame_%08d.png" -i "$INPUT" \
  -map 0:v -map 1:a? -c:v libx264 -pix_fmt yuv420p -c:a copy "$OUTPUT"

echo "== $(date) Done. Output: $OUTPUT =="

