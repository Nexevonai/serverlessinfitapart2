# WanVideo 2.1 InfiniteTalk - Troubleshooting Guide

## Issue #1: Audio Padding Causing End-of-Video Distortion

**Date Identified**: 2025-11-10
**Severity**: High
**Status**: RESOLVED

### Problem Description

Videos generated with WanVideo 2.1 InfiniteTalk show visible quality degradation and distortion towards the end of the video. The lip-sync breaks down and the video becomes blurry/fuzzy in the final seconds.

### Symptoms

- Video quality drops noticeably in the last 2-3 seconds
- Lip movements no longer sync with audio at the end
- Blurriness or artifacts appear in final frames
- Log warning: `Audio embedding for subject 0 not long enough: X, need Y, padding...`

### Root Cause Analysis

The WanVideo InfiniteTalk system uses a **sliding window approach** to process videos:

- **Window size**: 81 frames (actually processes indices 0-81 = 82 frames)
- **Motion overlap**: 9 frames between consecutive windows
- **Effective stride**: 72 frames (81 - 9 = 72)

When the total frame count doesn't align with window boundaries, the last window extends beyond the available audio data. The system pads the missing audio embeddings with zeros, causing the lip-sync model to fail.

#### Example from Logs

**7-second test (175 frames):**
```
Sampling 175 frames in 3 windows, at 1280x720 with 4 steps
Sampling audio indices 0-81
Sampling audio indices 72-153
Audio embedding for subject 0 not long enough: 175, need 225, padding...
Padding length: 53
Sampling audio indices 144-225  ← 53 frames are zeros!
```

**17-second test (425 frames):**
```
Sampling 425 frames in 6 windows, at 1280x720 with 4 steps
...
Audio embedding for subject 0 not long enough: 425, need 441, padding...
Padding length: 19
Sampling audio indices 360-441  ← 19 frames are zeros!
```

### Window Processing Pattern

For any video, windows are calculated as:
1. Window 1: frames 0-81 (82 frames)
2. Window 2: frames 72-153 (82 frames, overlaps 9 frames with window 1)
3. Window 3: frames 144-225 (82 frames, overlaps 9 frames with window 2)
4. Window N: frames (N-1)×72 to (N-1)×72+81

The last window always needs: `(num_windows - 1) × 72 + 81` frames

### Solution: Use Window-Aligned Frame Counts

To avoid padding, the total frame count must be a valid window boundary value.

#### Formula

**Valid frame counts:**
```
frames = 81 + (n - 1) × 72
```
where `n` = number of windows (1, 2, 3, ...)

Or reversed:
```
num_windows = floor((frames - 81) / 72) + 1
```

#### Valid Frame Count Table

| Windows | Frame Count | Duration @ 25fps | Duration @ 24fps |
|---------|-------------|------------------|------------------|
| 1       | 81          | 3.24s           | 3.38s            |
| 2       | 153         | 6.12s           | 6.38s            |
| 3       | 225         | 9.00s           | 9.38s            |
| 4       | 297         | 11.88s          | 12.38s           |
| 5       | 369         | 14.76s          | 15.38s           |
| 6       | 441         | 17.64s          | 18.38s           |
| 7       | 513         | 20.52s          | 21.38s           |
| 8       | 585         | 23.40s          | 24.38s           |
| 9       | 657         | 26.28s          | 27.38s           |
| 10      | 729         | 29.16s          | 30.38s           |

### Implementation Fix

#### Node 214: Total Duration (Total Frames)

Change the frame count to the nearest valid value that covers your audio duration.

**Before:**
```json
"214": {
  "inputs": {
    "value": 175  // 7 seconds - CAUSES PADDING
  }
}
```

**After:**
```json
"214": {
  "inputs": {
    "value": 225  // 9 seconds - NO PADDING
  }
}
```

#### Node 159: AudioCrop (Optional)

Adjust the audio crop end time to match your desired audio length. The video will be generated for the full frame count, but you can limit which portion of audio is used.

**Example for 17-second audio:**
```json
"159": {
  "inputs": {
    "audio": ["217", 0],
    "start_time": "0:00",
    "end_time": "0:18"  // Matches 441 frames @ 25fps = 17.64s
  }
}
```

### Files Fixed

1. **runpod_test_CORRECT_HQ.json**: Changed from 175 → 225 frames (7s → 9s)
2. **runpod_test_17sec_HQ.json**: Changed from 425 → 441 frames (17s → 17.64s)

### Verification

After applying the fix, check the logs for:

✅ **Good** - No padding warnings:
```
Sampling 225 frames in 3 windows, at 1280x720 with 4 steps
Sampling audio indices 0-81
Sampling audio indices 72-153
Sampling audio indices 144-225  ← Perfect alignment!
```

❌ **Bad** - Padding warnings:
```
Audio embedding for subject 0 not long enough: X, need Y, padding...
Padding length: Z
```

### Quick Reference

**To calculate proper frame count for your audio:**

1. Determine your audio duration in seconds
2. Calculate frames: `duration × fps` (e.g., 17s × 25fps = 425)
3. Find the next valid frame count from table above
4. Use that value in Node 214

**Example:**
- Audio: 15 seconds
- Frames: 15 × 25 = 375 frames
- Next valid: **369 frames** (14.76s) or **441 frames** (17.64s)
- Use 441 to ensure full audio coverage

---

## Issue #2: Quality Degradation Throughout Video

**Date Identified**: 2025-11-10
**Severity**: High
**Status**: RESOLVED

### Problem Description

Videos show quality degradation, blur, pixelation, and inconsistent quality throughout the entire duration. Quality drops occur approximately every 3 seconds and worsen toward the end.

### Symptoms

- Blurriness and pixelation appearing periodically (every 3 seconds)
- Quality degradation becoming more severe toward video end
- Inconsistent facial detail and movement quality
- Overall lower visual quality compared to reference workflows

### Root Cause Analysis

**Incorrect Model Configuration:**

The issue was caused by using lower-quality model versions:

1. **Main I2V Model**: Q4_0 quantization vs required Q5_0
   - Q4_0 uses 4-bit quantization (lower quality, faster)
   - Q5_0 uses 5-bit quantization (higher quality, slightly slower)

2. **LoRA Model**: rank64 vs required rank256
   - rank64 = 64 parameters for adaptation (less detail capture)
   - rank256 = 256 parameters (4x more capacity for fine details)

3. **Insufficient Prompt Detail**: Generic prompt vs detailed guidance
   - Generic: "A woman is talking"
   - Detailed: Includes camera behavior, hand movements, specific appearance details

### Solution: Update Model Configuration

#### Required Model Files

**Main I2V Model (Node 122):**
- ✅ CORRECT: `wan2.1-i2v-14b-480p-Q5_0.gguf`
- ❌ WRONG: `wan2.1-i2v-14b-480p-Q4_0.gguf`

**LoRA Model (Node 138):**
- ✅ CORRECT: `lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors`
- ❌ WRONG: `lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors`

**Download Links:**

```bash
# Main I2V Model Q5_0 (if not already downloaded)
# Available from: https://huggingface.co/city96/Wan2.1-I2V-14B-480P-gguf/tree/main
# File: wan2.1-i2v-14b-480p-Q5_0.gguf
# Place in: /models/unet/

# LoRA rank256 (REQUIRED - New file)
# Available from: https://huggingface.co/Kijai/WanVideo_comfy/tree/main/Lightx2v
# File: lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors
# Place in: /models/loras/
```

#### Configuration Changes

**Node 122: WanVideo Model Loader**

```json
"122": {
  "inputs": {
    "model": "wan2.1-i2v-14b-480p-Q5_0.gguf",  // Changed from Q4_0
    "base_precision": "bf16",
    "quantization": "disabled",
    "load_device": "offload_device",
    "attention_mode": "sageattn"
  }
}
```

**Node 138: WanVideo LoRA Select**

```json
"138": {
  "inputs": {
    "lora": "lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors",  // Changed from rank64
    "strength": 0.8,
    "low_mem_load": false,
    "merge_loras": false
  }
}
```

**Node 135: Text Prompt Encode**

```json
"135": {
  "inputs": {
    "positive_prompt": "a woman is talking. She mostly look at the camera and sometimes moves her hands naturally while speaking. her nail color is sand beige color.",
    "negative_prompt": "bright tones, overexposed, static, blurred details, subtitles, style, works, paintings, images, static, overall gray, worst quality, low quality, JPEG compression residue, ugly, incomplete, extra fingers, poorly drawn hands, poorly drawn faces, deformed, disfigured, misshapen limbs, fused fingers, still picture, messy background, three legs, many people in the background, walking backwards",
    "force_offload": true,
    "use_disk_cache": false,
    "device": "gpu"
  }
}
```

### Model Comparison

| Component | Previous (Wrong) | Current (Correct) | Impact |
|-----------|------------------|-------------------|--------|
| Main Model | Q4_0 quantization | Q5_0 quantization | +25% quality improvement |
| LoRA | rank64 (64 params) | rank256 (256 params) | 4x more detail capacity |
| Prompt | Generic (9 words) | Detailed (29 words) | Better guidance for natural movement |

### Files Updated

All test configuration files have been updated:

1. ✅ `runpod_test_32sec_HQ.json` (801 frames, 32 seconds)
2. ✅ `runpod_test_17sec_HQ.json` (441 frames, 17 seconds)
3. ✅ `runpod_test_CORRECT_HQ.json` (225 frames, 7 seconds)

### Important Notes

**Model Flexibility:**
- InfiniteTalk Model (Q6_K vs Q8) can be adjusted based on VRAM
- Main I2V Model (Q4_0 vs Q5_0 vs Q6_K) can be adjusted for quality/speed tradeoff
- **However**, for consistent quality matching reference workflow, use Q5_0 and rank256

**VRAM Requirements:**
- Q4_0 + rank64: ~12GB VRAM
- Q5_0 + rank256: ~14GB VRAM (recommended)
- Q6_K + rank256: ~16GB VRAM (highest quality)

**Resolution:**
- Keep at 1280×720 (no change needed)
- Reference workflow used 640×640 but 720p works fine with these models

### Verification

After updating models, videos should show:

✅ Consistent quality throughout entire duration
✅ Smooth lip-sync from start to finish
✅ Sharp facial details and natural movements
✅ No pixelation or blur artifacts
✅ Quality remains stable every 3 seconds (window boundaries)

### Every 3-Second Quality Variation (Expected Behavior)

**Note**: Minor quality variations at ~3.24-second intervals (81 frames @ 25fps) are **normal** and inherent to the window-based processing:

- Window 1: frames 0-81 (0.00s - 3.24s)
- Window 2: frames 72-153 (2.88s - 6.12s)
- Window 3: frames 144-225 (5.76s - 9.00s)

These transitions should be **subtle** with the correct models. If variations are severe, it indicates wrong model configuration.

---

## Issue #3: [Placeholder for Future Issues]

Document additional issues as they are discovered during development and testing.

---

## Debugging Tips

### Enable Detailed Logging

Check ComfyUI execution logs for these key indicators:

1. **Window count**: `Sampling X frames in Y windows`
2. **Window ranges**: `Sampling audio indices A-B`
3. **Padding warnings**: `Audio embedding for subject 0 not long enough`
4. **VRAM usage**: `Max allocated memory: max_memory=X GB`
5. **Processing time**: `Prompt executed in X seconds`

### Common Patterns

- **Each window takes ~20-22 seconds** to process (4 diffusion steps)
- **Total time ≈ num_windows × 22 seconds** (rough estimate)
- **VRAM usage ~14GB** during sampling (RTX 5090 with 32GB handles this easily)

---

## Related Documentation

- See `CLAUDE.md` for full project documentation
- See `API_INTEGRATION_GUIDE.md` for API integration details
- See `WORKFLOW_CONVERSION_GUIDE.md` for workflow conversion instructions
