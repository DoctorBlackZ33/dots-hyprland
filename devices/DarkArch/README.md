# DarkArch

Hardware-specific overlay for the DarkArch machine.

## Hardware

| GPU | PCI address | VRAM | Role |
| --- | --- | --- | --- |
| AMD Radeon RX 9070 (Navi 48) | 0000:03:00.0 | 16 GB | Primary display + LLM (llama-server, ROCm/Vulkan) |
| NVIDIA GeForce RTX 2080 Ti (GA102) | 0000:13:00.0 | 11 GB | Headless compute, LLM (ggml-rpc-server, CUDA) |
| AMD iGPU | 0000:7c:00.0 | 2 GB | Idle spare |

Both LLM backends occupy their GPU's VRAM while a model is loaded, so
anything else needing GPU memory must check for free VRAM at launch time.
See `local/.local/bin/handy-launch` for the launch and device-pinning logic.

## Deploy

```bash
system update --device DarkArch
```

## Overlay contents

- `.config/handy-launch.conf` — per-machine tuning for `handy-launch`
  (SUPER+ALT+V dictation): model ID, 2080 Ti GPU pin, microphone, mute
  routing. The fork binary's built-in VRAM gate decides GPU vs CPU at each
  session start.
