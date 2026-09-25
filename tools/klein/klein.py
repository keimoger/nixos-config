"""Local Klein image generation with a pinned OpenVINO model and runtime."""

import argparse
import json
import math
import secrets
import sys
import time
from datetime import datetime
from pathlib import Path

MODEL = "circulus/flux2-klein-4b-int4-ov"
REVISION = "ce217b9d7d17a4f7dbb254233b213b67f9aa823e"


def main(*, model=MODEL, revision=REVISION, label="Klein INT4", folder="Klein",
         default_steps=4, default_guidance=1.0, local_model_dir=None):
    parser = argparse.ArgumentParser(description=f"Local {label} image generation with OpenVINO.")
    parser.add_argument("prompt", nargs="?")
    parser.add_argument("--device", choices=["CPU", "GPU", "NPU"], default="GPU",
                        help="GPU recommended; NPU is experimental and needs compatible compiler libraries")
    parser.add_argument("--devices", action="store_true", help="list available devices")
    parser.add_argument("--download", action="store_true", help="download the pinned model")
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--steps", type=int, default=default_steps)
    parser.add_argument("--guidance", type=float, default=default_guidance)
    parser.add_argument("--negative-prompt", help="undesired features (supported by DreamShaper)")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    import openvino as ov

    core = ov.Core()
    if args.devices:
        for device in core.available_devices:
            print(f"{device}: {core.get_property(device, 'FULL_DEVICE_NAME')}")
        return

    if not args.download and not args.prompt:
        parser.error("provide a prompt, --download, or --devices")
    if any(size < 256 or size > 2048 or size % 16 for size in (args.width, args.height)):
        parser.error("dimensions must be multiples of 16 between 256 and 2048")
    if args.steps < 1:
        parser.error("steps must be positive")
    if not math.isfinite(args.guidance) or args.guidance < 0:
        parser.error("guidance must be a finite non-negative number")
    if not args.download and args.device not in core.available_devices:
        parser.error(f"{args.device} unavailable; detected {core.available_devices}")

    from huggingface_hub import snapshot_download

    if args.download:
        if local_model_dir is not None:
            parser.error("run the DreamShaper launcher with --download to convert the model")
        print(snapshot_download(model, revision=revision, max_workers=2))
        return
    # Generation is offline once the explicit download step has completed.
    if local_model_dir is not None:
        model_dir = Path(local_model_dir)
        if not (model_dir / "export-info.json").exists():
            parser.error("model is not prepared; run the DreamShaper launcher with --download first")
    else:
        model_dir = snapshot_download(model, revision=revision, local_files_only=True)

    import openvino_genai as genai
    from PIL import Image

    seed = args.seed if args.seed is not None else secrets.randbits(32)
    output = args.output or (
        Path.home() / "Pictures" / folder /
        f"{datetime.now():%Y%m%d-%H%M%S}-{seed}.png"
    )
    output = output.expanduser().resolve()
    if output.exists() or output.with_suffix(".json").exists():
        parser.error(f"output already exists: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    print(f"Loading {label}; {args.width}x{args.height}, {args.steps} steps, seed {seed}", flush=True)
    started = time.monotonic()
    pipeline = genai.Text2ImagePipeline(model_dir)
    pipeline.reshape(1, args.height, args.width, args.guidance)
    print(f"Compiling for {args.device}; the first run can take several minutes…", flush=True)
    try:
        if args.device == "NPU":
            pipeline.compile("CPU", "NPU", "CPU")
        else:
            pipeline.compile(args.device)
    except RuntimeError as error:
        print(f"Compilation failed on {args.device}: {error}", file=sys.stderr)
        if args.device == "NPU":
            print("Use --device GPU with this laptop's current compiler stack.", file=sys.stderr)
        return 1
    compiled = time.monotonic()
    print(f"Ready in {compiled - started:.1f}s. Generating…", flush=True)
    extra = {"negative_prompt": args.negative_prompt} if args.negative_prompt else {}
    result = pipeline.generate(
        args.prompt, width=args.width, height=args.height,
        num_inference_steps=args.steps, guidance_scale=args.guidance, rng_seed=seed,
        **extra,
    )
    generated = time.monotonic()
    Image.fromarray(result.data[0]).save(output, format="PNG")
    output.with_suffix(".json").write_text(json.dumps({
        "prompt": args.prompt, "model": model, "revision": revision,
        "device": args.device, "seed": seed, "width": args.width,
        "height": args.height, "steps": args.steps,
        "guidance": args.guidance, "negative_prompt": args.negative_prompt,
        "openvino": ov.__version__, "load_compile_seconds": compiled - started,
        "generation_seconds": generated - compiled,
    }, indent=2) + "\n")
    print(f"Saved {output}\nGeneration: {generated - compiled:.1f}s", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
