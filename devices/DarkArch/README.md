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
See `local/.local/bin/handy-launch` for the launch-time GPU pin and VRAM fallback it implements.

## Deploy

```bash
system update --device DarkArch
```

## Overlay contents

- `.config/handy-launch.conf` — model, GPU pin, microphone, and mute routing for
  `handy-launch` (SUPER+ALT+V dictation). The VRAM free/busy thresholds are built
  into the fork binary (see App binary).

## App binary

The `handy` binary is built from the fork
[DoctorBlackZ33/Handy](https://github.com/DoctorBlackZ33/Handy) (branch
`deploy/full`), which adds a per-session VRAM gate (use the pinned NVIDIA GPU
when enough VRAM is free at session start, otherwise strict CPU), `--model` /
`--quit` CLI overrides, and a CPU smoke test (`src-tauri/tests/whisper_smoke.rs`).
