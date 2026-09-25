# Local DreamShaper 8

Use it directly from Nushell:

```nu
~/nix-config/tools/dreamshaper/dreamshaper "adult figure study, classical atelier, tasteful non-explicit nude human form, soft window light, charcoal and oil painting"
```

Images and JSON metadata are written to `~/Pictures/DreamShaper/`. The launcher
uses your Arc GPU, a 7 GiB memory-pressure threshold, a 10 GiB hard limit, and a
2 GiB swap limit. Generate one image at a time on this 16 GB laptop.

```nu
# Reproduce a result or save elsewhere.
~/nix-config/tools/dreamshaper/dreamshaper "classical portrait" --seed 7 --output ~/Pictures/portrait.png

# Use a negative prompt and adjust the sampler settings.
~/nix-config/tools/dreamshaper/dreamshaper "figure study" --negative-prompt "text, watermark, extra limbs" --steps 30 --guidance 7.5

# List detected accelerators.
~/nix-config/tools/dreamshaper/dreamshaper --devices
```

The first setup command downloaded the original `Lykon/dreamshaper-8` revision
`a7e52b98680b1ba8ff7bce97c7f9f2e2e5337917` and converted it to FP16 OpenVINO
IR. The conversion is kept in `~/.local/share/dreamshaper`; the original
checkpoint remains in the Hugging Face cache. To repeat the setup after deleting
that prepared directory:

```nu
~/nix-config/tools/dreamshaper/dreamshaper --download
```

The model is a Stable Diffusion 1.5 fine-tune. Its model card describes improved
NSFW and realism capability in version 7 and broad artistic use in version 8.
This local launcher does not add a prompt or output filter; use it only for
lawful, consensual adult content and never for sexual content involving minors.

The Python environment is pinned in `pyproject.toml` and `uv.lock`, and uses
Python 3.12 plus OpenVINO 2026.4 from the repository's Nix package set. The
export path uses CPU-only PyTorch wheels, so it does not pull in CUDA packages.

Verified on `keibook` on 2026-09-24: DreamShaper 8 FP16, Arc GPU, 512×512,
25 steps, seed 7, generated `~/Pictures/DreamShaper/figure-study.png` in 4.3
seconds after a 7.4-second first compilation.
