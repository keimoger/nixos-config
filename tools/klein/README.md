# Local FLUX.2 Klein

Run directly from Nushell, from any directory, without rebuilding NixOS:

```nu
~/nix-config/tools/klein/klein "A cozy bookshop on the moon, watercolor illustration"
```

The executable launcher selects Bash internally through its shebang; your
interactive shell stays Nushell. Do not source the launcher or run it with
`nu`: invoke it as an external executable as shown above.

For a shorter command in your current Nushell session:

```nu
alias klein = ~/nix-config/tools/klein/klein
klein "A cozy bookshop on the moon, watercolor illustration"
```

Images and matching JSON files containing prompts, seeds, model revision, and
timings go into `~/Pictures/Klein/`. Generation uses the downloaded model offline.
The default is INT4 Klein 4B, Arc GPU, 512×512, four steps, guidance 1.0.

```nu
# See options and detected accelerators.
./tools/klein/klein --help
./tools/klein/klein --devices

# Reproduce a seed or choose an output path. Existing outputs are not overwritten.
./tools/klein/klein "A forest under moonlight" --seed 42 --output ~/Pictures/forest.png

# Larger images require more memory; start with the default on this laptop.
./tools/klein/klein "A forest under moonlight" --width 768 --height 512

# Required once on a fresh installation: approximately 4.5 GB.
./tools/klein/klein --download
```

The launcher applies a 7 GiB memory-pressure threshold, a 10 GiB hard memory
limit, and a 2 GiB swap limit through a user systemd scope. It requires a running
user systemd session. Generate one image at a time on this 16 GB laptop.

## Environment and model

- `shell.nix` gets Python 3.12, uv, and native runtime libraries from this
  repository's pinned NixOS package set. Intel drivers come from the active host.
- `pyproject.toml` and `uv.lock` pin OpenVINO/GenAI 2026.4 and Python dependencies.
  The Python environment lives in `~/.local/share/klein/venv` (or XDG_DATA_HOME).
  This is a Nix-backed environment with locked Python wheels, not a fully
  Nix-built Python application.
- Model: [circulus/flux2-klein-4b-int4-ov](https://huggingface.co/circulus/flux2-klein-4b-int4-ov),
  a community OpenVINO conversion of Black Forest Labs' distilled Klein 4B.
  Revision `ce217b9d7d17a4f7dbb254233b213b67f9aa823e` is pinned in `klein.py`.
  Files live in the Hugging Face cache, outside the Git repository.

## Verified on keibook, 2026-09-24

GPU generated `~/Pictures/Klein/first-light.png` at 512×512, four steps, seed 42:
14.6 seconds loading/compiling and 5.6 seconds generating. These are one-run
measurements, not guaranteed timings for other prompts or resolutions.

OpenVINO detects CPU, GPU, and NPU. The experimental `--device NPU` route runs
text encoding/decoding on CPU and denoising on NPU. It currently fails at compile
time with `NPU_COMPILER_DYNAMIC_QUANTIZATION` unsupported. The installed Linux
wheel also lacks the separate NPU compiler libraries, matching this
[upstream packaging issue](https://github.com/openvinotoolkit/openvino/issues/36374).
NPU inference is not validated; GPU is the working default. No system driver
replacement or NixOS activation was performed for this setup.
