"""DreamShaper defaults for the shared local image generator."""

import sys
from pathlib import Path

from settings import MODEL, MODEL_DIR, REVISION

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "klein"))
from klein import main

if __name__ == "__main__":
    raise SystemExit(main(
        model=MODEL, revision=REVISION, label="DreamShaper 8 FP16",
        folder="DreamShaper", default_steps=25, default_guidance=7.5,
        local_model_dir=MODEL_DIR,
    ))
