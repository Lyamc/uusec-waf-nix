#!/usr/bin/env python3
"""Copy /uuwaf out of an upstream image layer with usable permissions.

The image marks some directories mode 644, so a normal tar extract cannot
be traversed by the Nix builder. Whiteout entries are skipped.
"""

import os
import stat
import sys
import tarfile


def want(name: str) -> bool:
    normalized = name[2:] if name.startswith("./") else name
    if normalized != "uuwaf" and not normalized.startswith("uuwaf/"):
        return False
    return ".wh." not in normalized


def dest_for(root: str, name: str) -> str:
    normalized = name[2:] if name.startswith("./") else name
    return os.path.join(root, normalized)


def main() -> None:
    layer = sys.argv[1]
    root = sys.argv[2]
    os.makedirs(root, exist_ok=True)
    with tarfile.open(layer) as archive:
        for member in archive:
            if not want(member.name):
                continue
            dest = dest_for(root, member.name)
            if member.isdir():
                os.makedirs(dest, exist_ok=True)
                os.chmod(dest, 0o755)
                continue
            parent = os.path.dirname(dest)
            os.makedirs(parent, exist_ok=True)
            os.chmod(parent, 0o755)
            if member.issym():
                if os.path.lexists(dest):
                    os.remove(dest)
                os.symlink(member.linkname, dest)
                continue
            if member.islnk():
                target = dest_for(root, member.linkname)
                if os.path.lexists(dest):
                    os.remove(dest)
                os.link(target, dest)
                continue
            if not member.isfile():
                continue
            source = archive.extractfile(member)
            if source is None:
                continue
            with open(dest, "wb") as output:
                while True:
                    chunk = source.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
            mode = member.mode & 0o777
            if mode & 0o111:
                os.chmod(dest, mode | 0o755)
            else:
                os.chmod(dest, mode | 0o644)


if __name__ == "__main__":
    main()
