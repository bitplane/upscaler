#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:?usage: ./upscale.sh input.mp4 output.mp4}"
OUTPUT="${2:?usage: ./upscale.sh input.mp4 output.mp4}"

BASENAME="$(basename "$INPUT")"
WORKDIR="./work/${BASENAME}"
FRAMES="${WORKDIR}/frames"
DEBLOCKED="${WORKDIR}/deblocked"
UPSCALED="${WORKDIR}/upscaled"
RESTORED="${WORKDIR}/restored"
LOGFILE="${WORKDIR}/process.log"
BINDIR="./bin"

mkdir -p "$FRAMES" "$DEBLOCKED" "$UPSCALED" "$RESTORED" "$BINDIR"
exec > >(tee -a "$LOGFILE") 2>&1

echo "== $(date) Starting pipeline for $INPUT =="

# --- ensure deps ---
if ! command -v ffmpeg >/dev/null; then
  echo "Installing ffmpeg..."
  sudo apt update && sudo apt install -y ffmpeg
fi

REALESRGAN="${BINDIR}/realesrgan-ncnn-vulkan"
MODELS_DIR="${BINDIR}/models"
CODEFORMER="${BINDIR}/CodeFormer"

if [ ! -x "$REALESRGAN" ]; then
  echo "Building Real-ESRGAN from source..."
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

# Download models if missing
if [ ! -d "$MODELS_DIR" ]; then
  echo "Downloading Real-ESRGAN models..."
  cd "$BINDIR"
  wget -q https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-ubuntu.zip -O models.zip
  unzip -q models.zip "*/models/*"
  # The zip should contain a models directory or we need to extract it
  if [ -d "realesrgan-ncnn-vulkan/models" ]; then
    mv realesrgan-ncnn-vulkan/models .
    rm -rf realesrgan-ncnn-vulkan
  fi
  rm -f models.zip
  cd - >/dev/null
fi

# Setup CodeFormer if missing
if [ ! -d "$CODEFORMER" ]; then
  echo "Setting up CodeFormer..."
  cd "$BINDIR"
  git clone --depth=1 https://github.com/sczhou/CodeFormer.git
  cd CodeFormer
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt -q
  python basicsr/setup.py develop
  python scripts/download_pretrained_models.py facelib
  python scripts/download_pretrained_models.py CodeFormer
  deactivate
  cd - >/dev/null
fi

# --- step 1: extract frames ---
echo "🎞️ Extracting frames..."
ffmpeg -y -i "$INPUT" -qscale:v 2 "$FRAMES/frame_%08d.png"

# --- step 2: deblock ---
echo "🧽 Deblocking..."
ffmpeg -y -i "$FRAMES/frame_%08d.png" -vf deblock "$DEBLOCKED/frame_%08d.png"

# Save deblocked comparison video
echo "💾 Saving deblocked comparison..."
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$INPUT")
ffmpeg -y -framerate "$FPS" -i "$DEBLOCKED/frame_%08d.png" -i "$INPUT" \
  -map 0:v -map 1:a? -c:v libx264 -pix_fmt yuv420p -c:a copy "${WORKDIR}/01_deblocked.mp4"

# --- step 3: upscale ---
echo "🚀 Upscaling..."
"$REALESRGAN" -i "$DEBLOCKED/" -o "$UPSCALED/" -n realesr-animevideov3 -s 2 -m "$MODELS_DIR"

# Save upscaled comparison video
echo "💾 Saving upscaled comparison..."
ffmpeg -y -framerate "$FPS" -i "$UPSCALED/frame_%08d.png" -i "$INPUT" \
  -map 0:v -map 1:a? -c:v libx264 -pix_fmt yuv420p -c:a copy "${WORKDIR}/02_upscaled.mp4"

# --- step 4: face restoration ---
echo "👤 Restoring faces..."
cd "$CODEFORMER"
source venv/bin/activate
python inference_codeformer.py -w 0.7 --input_path "../../${UPSCALED}" --output_path "../../${RESTORED}/final_results"
deactivate
cd - >/dev/null

# Copy restored frames to main restored directory
cp "$RESTORED"/final_results/*.png "$RESTORED/" 2>/dev/null || true

# Save restored comparison video
echo "💾 Saving restored comparison..."
ffmpeg -y -framerate "$FPS" -i "$RESTORED/frame_%08d.png" -i "$INPUT" \
  -map 0:v -map 1:a? -c:v libx264 -pix_fmt yuv420p -c:a copy "${WORKDIR}/03_restored.mp4"

# --- step 5: reassemble final output ---
echo "🎬 Reassembling final output..."
ffmpeg -y -framerate "$FPS" -i "$RESTORED/frame_%08d.png" -i "$INPUT" \
  -map 0:v -map 1:a? -c:v libx264 -pix_fmt yuv420p -c:a copy "$OUTPUT"

echo "== $(date) Done. Output: $OUTPUT =="
echo "Comparison videos saved in $WORKDIR:"
echo "  - 01_deblocked.mp4"
echo "  - 02_upscaled.mp4"
echo "  - 03_restored.mp4"

