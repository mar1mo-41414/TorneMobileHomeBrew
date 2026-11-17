#!/usr/bin/env python3
"""Audit the dynamic-library dependencies of every Mach-O binary
under a directory tree (an extracted xcframework tarball, or an
.app bundle from an IPA).

Motivation (plan 58): the arib1 iOS libmpv archive carried a load
command for @rpath/SwiftCoreMedia.framework/SwiftCoreMedia, a
framework that exists neither in the app nor in iOS, and the app
crashed in dyld at launch. This audit mechanically verifies, before
shipping, that every recorded dependency can resolve on a device:

  - @rpath/<Name>.framework/<Name> (flat layout, iOS style) and
    @rpath/<Name>.framework/Versions/<ver>/<Name> (versioned
    layout, macOS style) : <Name>.framework must be present
    somewhere under the audited root.
  - any other @rpath/... dependency : error (bare dylib @rpath
    dependencies cannot resolve inside an app bundle).
  - @executable_path/... / @loader_path/... : the target must
    exist under the audited root.
  - absolute paths : must live under /System/Library/ or /usr/lib/
    (device system locations).

LC_LOAD_WEAK_DYLIB entries are reported as warnings, not errors:
a missing weak dependency does not stop dyld.

Usage: audit_load_commands.py <root-dir>
Exit code: 0 = clean, 1 = at least one error.
Requires: macOS (otool).
"""
import os
import struct
import subprocess
import sys

MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",  # MH_MAGIC / CIGAM (32)
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",  # MH_MAGIC_64 / CIGAM_64
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",  # FAT_MAGIC / CIGAM
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",  # FAT_MAGIC_64 / CIGAM_64
}

LOAD_CMDS = {"LC_LOAD_DYLIB", "LC_LOAD_WEAK_DYLIB", "LC_REEXPORT_DYLIB"}


def is_macho(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) in MACHO_MAGICS
    except OSError:
        return False


def load_commands(path):
    """Yield (cmd, name) for dylib load commands of a Mach-O file."""
    out = subprocess.run(
        ["otool", "-l", path], capture_output=True, text=True
    ).stdout
    cmd = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("cmd "):
            cmd = s.split(None, 1)[1]
        elif s.startswith("name ") and cmd in LOAD_CMDS:
            yield cmd, s.split(None, 1)[1].split(" (offset")[0]
            cmd = None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    root = os.path.abspath(sys.argv[1])

    frameworks = set()
    binaries = []
    for dirpath, dirnames, filenames in os.walk(root):
        for d in dirnames:
            if d.endswith(".framework"):
                frameworks.add(d)
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if os.path.isfile(p) and not os.path.islink(p) and is_macho(p):
                binaries.append(p)

    errors, warnings = [], []
    checked = 0
    for b in sorted(binaries):
        for cmd, dep in load_commands(b):
            checked += 1
            weak = cmd == "LC_LOAD_WEAK_DYLIB"
            sink = warnings if weak else errors
            rel = os.path.relpath(b, root)
            if dep.startswith("@rpath/"):
                rest = dep[len("@rpath/"):]
                parts = rest.split("/")
                fw = parts[0] if parts[0].endswith(".framework") else None
                stem = fw[:-len(".framework")] if fw else None
                # Framework deps come in two layouts: flat
                # (<Name>.framework/<Name>, iOS) and versioned
                # (<Name>.framework/Versions/<ver>/<Name>, macOS).
                # Both are fine as long as the framework is bundled;
                # anything else under @rpath is a bare dylib dep.
                is_framework_dep = fw is not None and (
                    (len(parts) == 2 and parts[1] == stem)
                    or (len(parts) == 4 and parts[1] == "Versions"
                        and parts[3] == stem)
                )
                if is_framework_dep:
                    if fw not in frameworks:
                        sink.append(f"{rel}: unresolved framework dep {dep}")
                else:
                    sink.append(f"{rel}: bare @rpath dylib dep {dep}")
            elif dep.startswith(("@executable_path/", "@loader_path/")):
                target = dep.split("/", 1)[1]
                if not any(
                    os.path.exists(os.path.join(root, p, target))
                    for p in ("", os.path.dirname(rel))
                ):
                    sink.append(f"{rel}: unresolved relative dep {dep}")
            elif dep.startswith("/"):
                if not dep.startswith(("/System/Library/", "/usr/lib/")):
                    sink.append(f"{rel}: non-system absolute dep {dep}")
            else:
                sink.append(f"{rel}: unusual dep {dep}")

    print(f"audited {len(binaries)} Mach-O binaries, {checked} load commands, "
          f"{len(frameworks)} frameworks present")
    for w in warnings:
        print(f"WARNING: {w}")
    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        print(f"FAILED: {len(errors)} unresolved dependencies")
        return 1
    print("OK: every dependency resolves")
    return 0


if __name__ == "__main__":
    sys.exit(main())
