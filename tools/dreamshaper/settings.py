import os
from pathlib import Path

MODEL = "Lykon/dreamshaper-8"
REVISION = "a7e52b98680b1ba8ff7bce97c7f9f2e2e5337917"
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
MODEL_DIR = DATA_HOME / "dreamshaper" / f"dreamshaper-8-{REVISION[:12]}-fp16-ov"
