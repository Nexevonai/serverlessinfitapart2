# WanVideo 2.1 InfiniteTalk - RunPod Serverless Project

## Project Overview

This project runs **WanVideo 2.1 InfiniteTalk** on RunPod serverless infrastructure. It takes a portrait image and audio file, then generates a lip-synced talking video with unlimited duration support.

### Original Project
- **Base**: Vibe Voice TTS (voice cloning workflow)
- **Converted to**: WanVideo InfiniteTalk (talking video generation)
- **Date Modified**: 2025-11-08

---

## How It Works

### Architecture
```
User API Request → RunPod Handler → ComfyUI (WanVideo) → R2 Storage → Video URL Response
```

### Workflow Pipeline
1. **LoadImage**: Loads portrait/face image
2. **LoadAudio**: Loads speech audio file
3. **AudioCrop**: Crops audio to specified duration (0:00 to 0:07)
4. **AudioSeparation**: Extracts vocals from background music/noise using Demucs
5. **ImageResizeKJv2**: Resizes image to 639×640 (model requirements)
6. **WanVideoClipVisionEncode**: Encodes image features using CLIP Vision
7. **MultiTalkWav2VecEmbeds**: Converts audio to embeddings using Wav2Vec2
8. **WanVideoImageToVideoMultiTalk**: Prepares image for video generation
9. **WanVideoSampler**: Main generation (4 steps with LoRA distillation)
10. **WanVideoDecode**: Decodes latents to video frames using VAE
11. **VHS_VideoCombine**: Combines frames into MP4 video (H.264, 25fps)

### Input Format
```json
{
  "input": {
    "image_url": "https://example.com/portrait.jpg",
    "audio_url": "https://example.com/speech.mp3",
    "workflow": { ... complete workflow JSON ... }
  }
}
```

### Output Format
```json
{
  "video": [
    "https://pub-xxx.r2.dev/uuid_filename.mp4"
  ]
}
```

---

## Technical Specifications

### Models Used

#### Core Models (Always Required)

| Model | Size | Purpose | Location |
|-------|------|---------|----------|
| **Wan2_1-InfiniteTalk_Single_Q8.gguf** | 2.65GB | InfiniteTalk audio-driven model (Q8) | `models/unet/` |
| **umt5-xxl-enc-bf16.safetensors** | 11.4GB | Text encoder (BF16 precision) | `models/text_encoders/` |
| **wan_2.1_vae.safetensors** | 254MB | VAE for latent encoding/decoding | `models/vae/` |
| **clip_vision_h.safetensors** | 1.26GB | CLIP Vision for image understanding | `models/clip_vision/` |
| **TencentGameMate/chinese-wav2vec2-base** | 1.52GB | Wav2Vec2 audio model (auto-download) | HF cache |
| **Demucs** | ~500MB | Audio separation model (auto-download) | HF cache |

#### Main I2V Model (Choose One)

| Model | Size | Quality | Speed | VRAM | Use Case |
|-------|------|---------|-------|------|----------|
| **wan2.1-i2v-14b-480p-Q4_0.gguf** | 10.2GB | Good | Fastest | 12GB | Fast generation, testing |
| **wan2.1-i2v-14b-480p-Q5_0.gguf** ⭐ | 12.7GB | **Excellent** | Fast | 14GB | **HQ production (recommended)** |
| wan2.1-i2v-14b-480p-Q6_K.gguf | 14.8GB | Best | Medium | 16GB | Maximum quality |

#### Distill LoRA (Choose One)

| Model | Size | Quality | Detail | VRAM | Use Case |
|-------|------|---------|--------|------|----------|
| **lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors** | 738MB | Good | Standard | +0.7GB | Fast generation |
| **lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors** ⭐ | 2.9GB | **Excellent** | **4x params** | +2.9GB | **HQ production (recommended)** |

**⭐ Recommended Configuration for High Quality:**
- Main Model: Q5_0 (~12.7GB)
- LoRA: rank256 (~2.9GB)
- **Total Size**: ~35GB download, ~14GB VRAM during generation
- **Quality**: Matches reference workflows, smooth consistent output

**Alternative Configuration for Speed/VRAM:**
- Main Model: Q4_0 (~10.2GB)
- LoRA: rank64 (~738MB)
- **Total Size**: ~27GB download, ~12GB VRAM during generation
- **Quality**: Good but may show minor artifacts

### Custom Nodes

1. **ComfyUI-WanVideoWrapper** (Required)
   - Main video generation nodes
   - Repository: https://github.com/kijai/ComfyUI-WanVideoWrapper

2. **audio-separation-nodes-comfyui** (Required)
   - Audio separation (vocal extraction)
   - Repository: https://github.com/christian-byrne/audio-separation-nodes-comfyui

3. **ComfyUI-VideoHelperSuite** (Required)
   - Video encoding and export (VHS_VideoCombine)
   - Repository: https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite

4. **ComfyUI-KJNodes** (Required)
   - Utility nodes (ImageResize, Constants)
   - Repository: https://github.com/kijai/ComfyUI-KJNodes

### Storage
- **Backend**: Cloudflare R2
- **Format**: H.264 MP4 (yuv420p, CRF 19)
- **Resolution**: 639×640 (configurable)
- **Frame Rate**: 25 FPS
- **Audio**: AAC codec (embedded in MP4)

### VRAM Requirements
- **Minimum**: 12GB VRAM (with block swapping enabled)
  - Uses 40 transformer blocks swapped to RAM
  - GGUF Q4_0 quantization
- **Recommended**: 16-24GB VRAM
  - Smoother generation
  - Less CPU↔GPU transfer
- **Optimal**: 24GB+ VRAM
  - Full model in VRAM
  - Fastest generation

### Generation Speed
- **With LoRA (4 steps)**: 10-30 seconds per 7-second video
- **Without LoRA (50 steps)**: 2-5 minutes per 7-second video
- **Processing breakdown**:
  - Audio separation: 5-10 seconds
  - Embedding generation: 3-5 seconds
  - Video generation: 10-20 seconds (4 steps)
  - VAE decode + encoding: 5-10 seconds

---

## Workflow Parameters

### Required Inputs

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `image_url` | String | Portrait/face image URL | `https://example.com/face.jpg` |
| `audio_url` | String | Speech audio file URL | `https://example.com/speech.mp3` |
| `workflow` | Object | Complete API workflow JSON | See `workflow_api_wanvideo.json` |

**Supported image formats**: JPG, JPEG, PNG
**Supported audio formats**: MP3, WAV, FLAC

### Optional: Custom Output Dimensions

You can override the default 639×640 output video size by passing optional `width` and `height` parameters:

```json
{
  "input": {
    "image_url": "https://example.com/portrait.jpg",
    "audio_url": "https://example.com/speech.mp3",
    "width": 480,    // Optional: custom output width
    "height": 832,   // Optional: custom output height
    "workflow": {...}
  }
}
```

**Behavior**:
- **Default**: 639×640 (if width/height not specified)
- **Custom dimensions**: Pass any width/height values
- **Requirements**: Dimensions should be divisible by 2 (model requirement)
- **Performance**: Larger dimensions = more VRAM + longer generation time

**Examples**:
- Portrait video: `"width": 480, "height": 832`
- Square video: `"width": 512, "height": 512`
- Landscape video: `"width": 832, "height": 480`
- Default: Don't pass width/height → uses 639×640

**Note**: For testing, any reasonable dimensions work (e.g., 480-1280px range). The workflow auto-resizes input images to match output dimensions.

### Video Duration Control

**Formula**: `Duration (seconds) = num_frames ÷ fps`

⚠️ **IMPORTANT: Frame Count Must Be Window-Aligned**

WanVideo InfiniteTalk uses 81-frame windows with 9-frame overlap. To avoid audio padding artifacts and end-of-video distortion, **use only these valid frame counts**:

| Frames | Duration @ 25fps | Windows |
|--------|------------------|---------|
| 81     | 3.24s           | 1       |
| 153    | 6.12s           | 2       |
| **225**    | **9.00s**           | **3**       |
| 297    | 11.88s          | 4       |
| 369    | 14.76s          | 5       |
| **441**    | **17.64s**          | **6**       |
| 513    | 20.52s          | 7       |
| 585    | 23.40s          | 8       |
| 657    | 26.28s          | 9       |
| 729    | 29.16s          | 10      |

**Formula**: `valid_frames = 81 + (n - 1) × 72` where n = number of windows

**Why This Matters**: Using non-aligned frame counts (like 175, 250, 425) causes the system to pad audio embeddings with zeros at the end, resulting in poor lip-sync and visible quality degradation in the final seconds of the video.

**Examples**:
- ❌ 7 seconds: 175 frames → causes 53 frames of padding → distortion
- ✅ 7 seconds: Use **225 frames** (9s) instead → no padding, perfect quality
- ❌ 17 seconds: 425 frames → causes 19 frames of padding → distortion
- ✅ 17 seconds: Use **441 frames** (17.64s) instead → no padding, perfect quality

See `TROUBLESHOOTING.md` for detailed explanation of the audio padding issue.

**Note**: The "InfiniteTalk" feature means there's no hardcoded duration limit. Generate videos of any length by using window-aligned frame counts.

### Workflow Configuration

**Main parameters** (in workflow JSON):

```json
{
  "214": {
    "inputs": {"value": 175},  // num_frames (video length)
    "class_type": "INTConstant"
  },
  "229": {
    "inputs": {"value": 25.0},  // fps (frames per second)
    "class_type": "PrimitiveFloat"
  },
  "210": {
    "inputs": {"value": 639},  // width (must be divisible by 2)
    "class_type": "INTConstant"
  },
  "211": {
    "inputs": {"value": 640},  // height (must be divisible by 2)
    "class_type": "INTConstant"
  }
}
```

### Audio Processing

**AudioCrop** (Node 159):
- `start_time`: "0:00" (start timestamp)
- `end_time`: "0:07" (end timestamp)

**AudioSeparation** (Node 170):
- Automatically extracts vocals
- Removes background music, noise
- Uses Demucs model
- Output: 4 stems (Bass, Drums, Other, Vocals)
- Only Vocals are used for lip-sync

**Audio Embeddings** (Node 194):
- `normalize_loudness`: true (auto-adjust volume)
- `audio_scale`: 1.0 (control audio influence)
- `audio_cfg_scale`: 1.0 (classifier-free guidance for audio)

### Text Prompt (Optional)

**WanVideoTextEncode** (Node 135):
- `positive_prompt`: "A woman is talking"
- `negative_prompt`: "bright tones, overexposed, static, blurred details, subtitles..."

**Note**: Text prompts have minimal effect on InfiniteTalk. The audio drives the lip-sync.

### Generation Settings

**WanVideoSampler** (Node 213):
- `steps`: 4 (with LoRA) or 50 (without LoRA)
- `cfg`: 1.0 (classifier-free guidance)
- `shift`: 11.0 (timestep shifting)
- `scheduler`: "flowmatch_distill" (with LoRA)
- `seed`: 0 (random) or fixed integer
- `force_offload`: true (aggressive VRAM management)

### Memory Optimization

**WanVideoBlockSwap** (Node 134):
- `blocks_to_swap`: 40 (offload transformer blocks to RAM)
- `offload_img_emb`: false
- `offload_txt_emb`: false
- `use_non_blocking`: true

This allows 12GB VRAM GPUs to run the 14B parameter model.

---

## Environment Variables Required

```bash
R2_ENDPOINT_URL=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_ACCESS_KEY_ID=your_access_key_here
R2_SECRET_ACCESS_KEY=your_secret_key_here
R2_BUCKET_NAME=your_bucket_name
R2_PUBLIC_URL=https://pub-xxx.r2.dev
```

**Setup**:
1. Create Cloudflare R2 bucket
2. Generate R2 API token
3. Enable public access on bucket
4. Set environment variables in RunPod endpoint

---

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Container setup, model downloads, custom nodes |
| `src/rp_handler.py` | RunPod serverless handler (image+audio input, video output) |
| `src/ComfyUI_API_Wrapper.py` | ComfyUI API client (WebSocket communication) |
| `src/start.sh` | Container startup script |
| `workflow_api_wanvideo.json` | WanVideo workflow (API format, all nodes defined) |
| `input.json` | Example API request |
| `response.json` | Example API response |
| `CLAUDE.md` | This documentation file |

---

## Build & Deploy

### Local Build (Optional)
```bash
docker build -t wanvideo-runpod .
```

**Note**: Build takes 30-60 minutes due to model downloads (~23GB)

### Deploy to RunPod

1. **Create Serverless Endpoint**:
   - Go to RunPod → Serverless → New Endpoint
   - Choose "Custom Container"

2. **Configure Container**:
   - Container Image: Your Docker image URL
   - Container Disk: 50-100GB (for models + output)
   - GPU Type: RTX 4090, A6000, or similar (16GB+ VRAM)

3. **Set Environment Variables**:
   - Add all R2 variables from above
   - Set `COMFYUI_PATH=/root/comfy/ComfyUI`

4. **Set Timeouts**:
   - Idle Timeout: 5 minutes
   - Max Execution Time: 600 seconds (10 minutes)

5. **Deploy**:
   - Click "Deploy"
   - Wait for build to complete
   - Check logs for model loading

### Testing

Send test request to endpoint:
```json
{
  "input": {
    "image_url": "https://your-cdn.com/portrait.jpg",
    "audio_url": "https://your-cdn.com/speech.mp3",
    "workflow": { ...workflow_api_wanvideo.json contents... }
  }
}
```

Expected response time: 30-60 seconds for 7-second video

---

## Model Download Links

### Main Models (Required)

**WAN 2.1 Main Model** (GGUF format):
- **Q4_0** (10.2GB, recommended): https://huggingface.co/city96/Wan2.1-I2V-14B-480P-gguf/resolve/main/wan2.1-i2v-14b-480p-Q4_0_2.gguf
- Q3_K_M (8.59GB, lower quality)
- Q4_K_M (11.3GB, better quality)
- Q8_0 (18.1GB, highest quality)

**InfiniteTalk Model** (GGUF):
- **Q6_K** (2.04GB): https://huggingface.co/Kijai/WanVideo_comfy_GGUF/resolve/main/InfiniteTalk/Wan2_1-InfiniteTalk_Single_Q6_K_2.gguf

**Text Encoder**:
- **FP8** (6.73GB, recommended): https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-fp8_e4m3fn.safetensors
- BF16 (11.4GB, higher VRAM)

**VAE**:
- https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors

**CLIP Vision**:
- https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors

**Distill LoRA** (Optional, for 4-step generation):
- https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/Wan2.1-lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors

### Auto-Downloaded Models
These download automatically on first use:
- **Wav2Vec2**: TencentGameMate/chinese-wav2vec2-base (~1.52GB)
- **Demucs**: Audio separation model (~500MB)

---

## Troubleshooting

### ⚠️ CRITICAL ISSUES

**End-of-Video Distortion (Audio Padding)**:
- **Symptom**: Video becomes blurry/fuzzy in final seconds, lip-sync breaks down
- **Cause**: Frame count not aligned with 81-frame window boundaries
- **Solution**: Use window-aligned frame counts only (see table in "Video Duration Control" section)
- **Details**: See `TROUBLESHOOTING.md` for full explanation

**Quick Fix**:
- Instead of 175 frames → use **225 frames**
- Instead of 425 frames → use **441 frames**
- Check logs for: `Audio embedding for subject 0 not long enough` warning

### Common Issues

**1. Out of VRAM**:
- Solution: Increase `blocks_to_swap` in node 134 to 50-60
- Or use smaller model quantization (Q3_K_M)
- Or enable `tiled_vae` in node 192

**2. Slow generation**:
- Check if LoRA is loaded (node 138)
- Verify `scheduler` is "flowmatch_distill" (node 213)
- Ensure GPU utilization is high (check RunPod metrics)

**3. Poor lip-sync quality**:
- Ensure audio separation is working (check node 170)
- Try different `audio_scale` values (0.8-1.2)
- Use clearer speech audio input
- Ensure portrait shows full face

**4. Video not uploaded to R2**:
- Check R2 environment variables
- Verify bucket has public access
- Check worker logs for upload errors
- Ensure network connectivity

**5. Build fails**:
- Check HuggingFace model URLs are correct
- Verify container disk size is sufficient (50GB+)
- Check custom node repos are accessible
- Review build logs for specific errors

### Debug Mode

Enable debug logging in handler:
```python
# Add at top of rp_handler.py
import logging
logging.basicConfig(level=logging.DEBUG)
```

Check ComfyUI logs:
```bash
# In container
tail -f /root/comfy/ComfyUI/comfyui.log
```

---

## Notes

- Workflow format: **API format** (not UI format)
- Audio files saved to: `/root/comfy/ComfyUI/input/`
- Image files saved to: `/root/comfy/ComfyUI/input/`
- Output directory: `/root/comfy/ComfyUI/output/`
- ComfyUI runs on: `http://127.0.0.1:8188`
- Video encoding: H.264 MP4, yuv420p, CRF 19, 25fps
- Audio in video: AAC codec, 128kbps

---

## Performance Benchmarks

Based on RunPod RTX 4090 (24GB VRAM):

| Video Length | Steps | Generation Time | VRAM Usage |
|--------------|-------|-----------------|------------|
| 7 seconds | 4 (LoRA) | 15-25 seconds | 18GB |
| 7 seconds | 50 (no LoRA) | 120-180 seconds | 18GB |
| 10 seconds | 4 (LoRA) | 20-30 seconds | 18GB |
| 15 seconds | 4 (LoRA) | 30-45 seconds | 18GB |

**Note**: Times include audio processing, embedding generation, and video encoding.

---

## References

- **WanVideo GitHub**: https://github.com/kijai/ComfyUI-WanVideoWrapper
- **WanVideo Models**: https://huggingface.co/Kijai/WanVideo_comfy
- **Main Model (GGUF)**: https://huggingface.co/city96/Wan2.1-I2V-14B-480P-gguf
- **ComfyUI**: https://github.com/comfyanonymous/ComfyUI
- **Original Base Project**: Vibe Voice TTS (upscale2flare)

---

## Version History

- **2025-11-08**: Converted from Vibe Voice TTS to WanVideo 2.1 InfiniteTalk
- **Previous**: Vibe Voice TTS voice cloning workflow
- **Original**: upscale2flare image upscaling project

.
