# --- 1. 基础镜像和环境设置 ---
FROM runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ="Etc/UTC"
ENV COMFYUI_PATH=/root/comfy/ComfyUI
ENV VENV_PATH=/venv

# --- 2. 安装系统依赖 ---
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ffmpeg \
    wget \
    unzip \
    build-essential \
    ninja-build \
    && apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# --- 3. 设置 Python 虚拟环境 (VENV) ---
RUN python -m venv $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"
RUN /venv/bin/python -m pip install --upgrade pip

# --- 4. 安装 ComfyUI 和核心 Python 包 ---
RUN /venv/bin/python -m pip install comfy-cli
RUN comfy --skip-prompt install --nvidia --cuda-version 12.9

# --- 关键修改：明确安装所有handler需要的依赖 ---
RUN /venv/bin/python -m pip install \
    opencv-python \
    imageio-ffmpeg \
    runpod \
    requests \
    websocket-client \
    boto3 \
    huggingface-hub

# --- 5. 创建 WanVideo 模型目录 ---
RUN mkdir -p \
    $COMFYUI_PATH/models/unet \
    $COMFYUI_PATH/models/text_encoders \
    $COMFYUI_PATH/models/vae \
    $COMFYUI_PATH/models/clip_vision \
    $COMFYUI_PATH/models/loras

# --- 6. 下载 WanVideo 模型文件 ---
# Main I2V model Q4_0 (quantized, ~10.2GB) - for faster generation
RUN /venv/bin/huggingface-cli download city96/Wan2.1-I2V-14B-480P-gguf \
    wan2.1-i2v-14b-480p-Q4_0.gguf \
    --local-dir $COMFYUI_PATH/models/unet \
    --local-dir-use-symlinks False

# Main I2V model Q5_0 (quantized, ~12.7GB) - for higher quality (REQUIRED for HQ workflows)
RUN /venv/bin/huggingface-cli download city96/Wan2.1-I2V-14B-480P-gguf \
    wan2.1-i2v-14b-480p-Q5_0.gguf \
    --local-dir $COMFYUI_PATH/models/unet \
    --local-dir-use-symlinks False

# InfiniteTalk model Q8 (~2.65GB) - Jockerai's version
RUN /venv/bin/huggingface-cli download Kijai/WanVideo_comfy_GGUF \
    InfiniteTalk/Wan2_1-InfiniteTalk_Single_Q8.gguf \
    --local-dir /tmp/infinitetalk_dl && \
    mv /tmp/infinitetalk_dl/InfiniteTalk/Wan2_1-InfiniteTalk_Single_Q8.gguf \
       $COMFYUI_PATH/models/unet/Wan2_1-InfiniteTalk_Single_Q8.gguf && \
    rm -rf /tmp/infinitetalk_dl

# Text encoder (BF16, ~11.4GB) - Jockerai's version
RUN wget -O $COMFYUI_PATH/models/text_encoders/umt5-xxl-enc-bf16.safetensors \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors"

# VAE (~254MB)
RUN wget -O $COMFYUI_PATH/models/vae/wan_2.1_vae.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"

# CLIP Vision (~1.26GB)
RUN wget -O $COMFYUI_PATH/models/clip_vision/clip_vision_h.safetensors \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"

# Distill LoRA rank64 (~738MB - for faster generation)
RUN /venv/bin/huggingface-cli download Kijai/WanVideo_comfy \
    Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors \
    --local-dir /tmp/lora_dl_64 && \
    mv /tmp/lora_dl_64/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors \
       $COMFYUI_PATH/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors && \
    rm -rf /tmp/lora_dl_64

# Distill LoRA rank256 (~2.9GB - for higher quality, REQUIRED for HQ workflows)
RUN /venv/bin/huggingface-cli download Kijai/WanVideo_comfy \
    Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors \
    --local-dir /tmp/lora_dl_256 && \
    mv /tmp/lora_dl_256/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors \
       $COMFYUI_PATH/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank256_bf16.safetensors && \
    rm -rf /tmp/lora_dl_256

# Note: Wav2Vec2 and Demucs models will auto-download on first use

# --- 7. 安装 WanVideo 自定义节点 ---
# Main WanVideo wrapper
RUN git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    $COMFYUI_PATH/custom_nodes/ComfyUI-WanVideoWrapper && \
    cd $COMFYUI_PATH/custom_nodes/ComfyUI-WanVideoWrapper && \
    /venv/bin/python -m pip install -r requirements.txt || true

# Audio separation nodes
RUN git clone https://github.com/christian-byrne/audio-separation-nodes-comfyui.git \
    $COMFYUI_PATH/custom_nodes/audio-separation-nodes-comfyui && \
    cd $COMFYUI_PATH/custom_nodes/audio-separation-nodes-comfyui && \
    /venv/bin/python -m pip install -r requirements.txt || true

# Video helper suite (for VHS_VideoCombine)
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    $COMFYUI_PATH/custom_nodes/ComfyUI-VideoHelperSuite && \
    cd $COMFYUI_PATH/custom_nodes/ComfyUI-VideoHelperSuite && \
    /venv/bin/python -m pip install -r requirements.txt || true

# KJNodes (utilities)
RUN git clone https://github.com/kijai/ComfyUI-KJNodes.git \
    $COMFYUI_PATH/custom_nodes/ComfyUI-KJNodes && \
    cd $COMFYUI_PATH/custom_nodes/ComfyUI-KJNodes && \
    /venv/bin/python -m pip install -r requirements.txt || true

# --- 8. 安装 WanVideo Python 依赖 ---
RUN /venv/bin/python -m pip install \
    transformers \
    soundfile \
    librosa \
    einops \
    safetensors \
    demucs \
    accelerate

# --- 9. 安装 SageAttention (单独安装以避免编译问题) ---
# Only compile for RTX 5090 (sm_120) to speed up build time
ENV TORCH_CUDA_ARCH_LIST="12.0"
RUN /venv/bin/python -m pip install wheel setuptools
RUN /venv/bin/python -m pip install sageattention --no-build-isolation

# --- 8. 复制脚本并设置权限 ---
# --- 关键修改：不再复制 workflow_api.json ---
COPY src/start.sh /root/start.sh
COPY src/rp_handler.py /root/rp_handler.py
COPY src/ComfyUI_API_Wrapper.py /root/ComfyUI_API_Wrapper.py

RUN chmod +x /root/start.sh

# --- 9. 定义容器启动命令 ---
CMD ["/root/start.sh"]
