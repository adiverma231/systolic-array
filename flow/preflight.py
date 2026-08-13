"""Check the local prerequisites for the Stage 4 OpenLane hardening flow."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path


REQUIRED_TOOLS = ("openlane", "yosys", "openroad", "magic", "netgen")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--require-tools",
        action="store_true",
        help="return failure when any RTL-to-GDS tool is missing",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    config = root / "flow" / "config.json"
    print(f"design root: {root}")
    print(f"config:      {config}")

    missing = []
    for tool in REQUIRED_TOOLS:
        path = shutil.which(tool)
        if path:
            print(f"{tool:9} OK  {path}")
        else:
            print(f"{tool:9} MISSING")
            missing.append(tool)

    for variable in ("PDK_ROOT", "PDK"):
        value = os.environ.get(variable)
        print(f"{variable:9} {value if value else 'unset'}")

    if args.require_tools and missing:
        print("missing required Stage 4 tools: " + ", ".join(missing), file=sys.stderr)
        return 2
    if missing:
        print("preflight incomplete: install OpenLane 2 and the sky130A PDK before running the flow")
    else:
        print("preflight passed: all required Stage 4 executables are available")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
