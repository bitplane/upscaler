# Video Upscale Pipeline

Restores low-res/blocky videos using deblocking, AI upscaling, and face restoration.

## Dependencies

### System packages
```bash
sudo apt update && sudo apt install -y \
  ffmpeg \
  git \
  cmake \
  build-essential \
  libvulkan1 \
  vulkan-tools \
  libopencv-dev \
  glslang-tools \
  python3 \
  python3-venv \
  python3-pip \
  wget \
  unzip
```

### Auto-installed components
The script automatically downloads/builds:
- Real-ESRGAN-ncnn-vulkan (compiled from source)
- Real-ESRGAN models (2x/3x/4x anime and general models)
- Real-CUGAN-ncnn-vulkan (compiled from source)
- Real-CUGAN models (optimized for compressed/degraded video)
- CodeFormer (with dedicated venv for face restoration)

## Usage

```bash
./upscale.sh input.mp4 output.mp4
```

## Pipeline stages

1. **Extract frames** - Decode video to PNG frames
2. **Deblock** - Remove compression artifacts with ffmpeg deblock filter
3. **Upscale** - 2x AI upscaling using Real-CUGAN (denoise level 3)
4. **Face restoration** - Restore faces using CodeFormer (w=0.7)
5. **Reassemble** - Encode back to video with original audio

## Output files

- `output.mp4` - Final processed video
- `work/<input>/01_deblocked.mp4` - After deblocking
- `work/<input>/02_upscaled.mp4` - After 2x upscale
- `work/<input>/03_restored.mp4` - After face restoration
- `work/<input>/process.log` - Full processing log

## Configuration

Edit `upscale.sh` to adjust:
- Denoise level (`-n` parameter, line 133: -1/0/1/2/3, higher = more denoising)
- Upscale factor (`-s` parameter, line 133: 2/3/4)
- Face restoration fidelity (`-w` parameter, line 143: 0-1, higher = more faithful to original)
