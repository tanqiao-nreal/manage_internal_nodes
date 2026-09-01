#!/usr/bin/env python3
"""Encode a PowerShell script file as a base64 payload for -EncodedCommand.

PowerShell's -EncodedCommand expects the script encoded as UTF-16LE, then
base64'd. Passing a script this way avoids the nested-quoting problems of
embedding a multi-line script inside an ssh command line.
"""

import base64
import sys


def main() -> None:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <script.ps1>", file=sys.stderr)
        raise SystemExit(1)

    with open(sys.argv[1], encoding="utf-8") as f:
        script = f.read()

    print(base64.b64encode(script.encode("utf-16-le")).decode())


if __name__ == "__main__":
    main()
