"""Download the original DreamShaper 8 weights and export an FP16 OpenVINO pipeline."""

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from settings import MODEL, MODEL_DIR, REVISION


def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    from filelock import FileLock

    MODEL_DIR.parent.mkdir(parents=True, exist_ok=True)
    with FileLock(str(MODEL_DIR) + ".lock"):
        if (MODEL_DIR / "export-info.json").exists():
            print(f"Model already prepared: {MODEL_DIR}", flush=True)
            return
        if MODEL_DIR.exists():
            raise RuntimeError(f"Incomplete model directory exists: {MODEL_DIR}")

        from diffusers import EulerDiscreteScheduler
        from optimum.exporters.openvino import main_export
        from optimum.intel.openvino.configuration import OVConfig
        import openvino

        print(f"Downloading and converting {MODEL} at {REVISION}…", flush=True)
        # Export in a temporary sibling directory, so failures never leave an
        # apparently ready model at MODEL_DIR. Original weights stay cached.
        with tempfile.TemporaryDirectory(prefix=".export-", dir=MODEL_DIR.parent) as temporary:
            destination = Path(temporary) / "model"
            main_export(
                model_name_or_path=MODEL,
                revision=REVISION,
                output=destination,
                task="text-to-image",
                library_name="diffusers",
                variant="fp16",
                ov_config=OVConfig(dtype="fp16"),
                convert_tokenizer=True,
                trust_remote_code=False,
                model_loading_kwargs={"safety_checker": None, "requires_safety_checker": False},
            )
            # GenAI does not implement the original DEIS scheduler. Euler uses
            # the same checkpoint and noise schedule, with a supported sampler.
            scheduler_dir = destination / "scheduler"
            scheduler_config = json.loads((scheduler_dir / "scheduler_config.json").read_text())
            EulerDiscreteScheduler.from_config(scheduler_config).save_pretrained(scheduler_dir)
            index_path = destination / "model_index.json"
            index = json.loads(index_path.read_text())
            index["scheduler"] = ["diffusers", "EulerDiscreteScheduler"]
            index_path.write_text(json.dumps(index, indent=2) + "\n")
            (destination / "export-info.json").write_text(json.dumps({
                "source": MODEL,
                "revision": REVISION,
                "precision": "fp16",
                "scheduler": "EulerDiscreteScheduler",
                "openvino": openvino.__version__,
                "environment_lock_sha256": hashlib.sha256(
                    Path(__file__).with_name("uv.lock").read_bytes()
                ).hexdigest(),
            }, indent=2) + "\n")
            destination.rename(MODEL_DIR)
        print(f"Model ready: {MODEL_DIR}", flush=True)


if __name__ == "__main__":
    main()
