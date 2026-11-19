#!/usr/bin/env python3
"""Standalone libmpv probe (same style as the section 68 Windows probe).

Loads a libmpv.so.2 directly, opens a broadcast TS, and reports:
  - whether the file loaded at all (FILE_LOADED vs error),
  - the track list (video / audio / sub codecs),
  - subtitle text samples obtained by stepping through the file with
    the ARIB caption track selected.

Usage: probe_libmpv.py <path-to-libmpv.so.2> <media-file>
Exit status 0 iff the file loaded, a sub track with codec
"arib_caption" exists, and at least one non-empty subtitle text
sample was captured.
"""

import ctypes
import sys
import time

MPV_EVENT_NONE = 0
MPV_EVENT_END_FILE = 7
MPV_EVENT_FILE_LOADED = 8


def main() -> int:
    libmpv_path, media = sys.argv[1], sys.argv[2]
    mpv = ctypes.CDLL(libmpv_path, mode=ctypes.RTLD_GLOBAL)

    mpv.mpv_create.restype = ctypes.c_void_p
    mpv.mpv_get_property_string.restype = ctypes.c_void_p
    mpv.mpv_wait_event.restype = ctypes.c_void_p

    handle = mpv.mpv_create()
    if not handle:
        print("FAIL: mpv_create returned NULL")
        return 1

    def set_opt(name: str, value: str) -> None:
        rc = mpv.mpv_set_option_string(
            handle, name.encode(), value.encode()
        )
        if rc < 0:
            print(f"warn: set_option {name}={value} -> {rc}")

    set_opt("config", "no")
    set_opt("vo", "null")
    set_opt("ao", "null")
    set_opt("terminal", "no")
    set_opt("load-scripts", "no")
    set_opt("ytdl", "no")

    rc = mpv.mpv_initialize(ctypes.c_void_p(handle))
    if rc < 0:
        print(f"FAIL: mpv_initialize -> {rc}")
        return 1

    def get_prop(m, h, name):
        p = m.mpv_get_property_string(ctypes.c_void_p(h), name.encode())
        if not p:
            return None
        s = ctypes.cast(p, ctypes.c_char_p).value.decode("utf-8", "replace")
        m.mpv_free(ctypes.c_void_p(p))
        return s

    print("mpv version:", get_prop(mpv, handle, "mpv-version"))

    mpv.mpv_command(
        ctypes.c_void_p(handle),
        (ctypes.c_char_p * 3)(b"loadfile", media.encode(), None),
    )

    loaded = False
    deadline = time.time() + 30
    while time.time() < deadline:
        ev_ptr = mpv.mpv_wait_event(ctypes.c_void_p(handle), ctypes.c_double(0.5))
        if not ev_ptr:
            continue
        event_id = ctypes.cast(ev_ptr, ctypes.POINTER(ctypes.c_int)).contents.value
        if event_id == MPV_EVENT_FILE_LOADED:
            loaded = True
            break
        if event_id == MPV_EVENT_END_FILE:
            break
    print("FILE_LOADED" if loaded else "FAIL: file did not load")
    if not loaded:
        return 1

    count = int(get_prop(mpv, handle, "track-list/count") or 0)
    tracks = []
    sub_id = None
    for i in range(count):
        t = {
            "type": get_prop(mpv, handle, f"track-list/{i}/type"),
            "codec": get_prop(mpv, handle, f"track-list/{i}/codec"),
            "id": get_prop(mpv, handle, f"track-list/{i}/id"),
        }
        tracks.append(t)
        print(f"track {i}: {t['type']} codec={t['codec']} id={t['id']}")
        if t["type"] == "sub" and t["codec"] == "arib_caption":
            sub_id = t["id"]
    duration = float(get_prop(mpv, handle, "duration") or 0)
    print(f"duration: {duration:.1f}s")

    if sub_id is None:
        print("FAIL: no arib_caption sub track")
        return 1

    mpv.mpv_set_property_string(
        ctypes.c_void_p(handle), b"sid", str(sub_id).encode()
    )

    samples = []
    t = 1.0
    while t < max(duration - 1, 1.0):
        mpv.mpv_command(
            ctypes.c_void_p(handle),
            (ctypes.c_char_p * 4)(b"seek", str(t).encode(), b"absolute", None),
        )
        # Let the seek land and the subtitle decoder produce the cue
        # active at the target position.
        for _ in range(6):
            time.sleep(0.15)
            txt = get_prop(mpv, handle, "sub-text")
            if txt and txt.strip():
                if txt not in samples:
                    samples.append(txt)
                break
        t += 4.0

    print(f"subtitle samples ({len(samples)}):")
    for s in samples[:8]:
        print("  |", s.replace("\n", " / ")[:80])

    mpv.mpv_terminate_destroy(ctypes.c_void_p(handle))
    if samples:
        print("PROBE OK")
        return 0
    print("FAIL: no subtitle text captured")
    return 1


if __name__ == "__main__":
    sys.exit(main())
