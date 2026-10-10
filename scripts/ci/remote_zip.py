#!/usr/bin/env python3
"""List or extract members of a remote zip (for example a Godot .tpz) using HTTP Range requests.

Usage:
  python3 -I remote_zip.py list URL
  python3 -I remote_zip.py extract URL DEST_DIR MEMBER [MEMBER ...]

Only the central directory and the requested members are downloaded. zipfile checks each
member's CRC-32 while extracting, and scripts/ci/install-godot.sh then checks pinned SHA-256s.
Stdlib only (urllib, zipfile), so it runs on a stock ubuntu-24.04 runner.
"""

import http.client
import io
import os
import sys
import time
import urllib.request
import zipfile

ATTEMPTS = 4
# Network trouble: socket errors, HTTP errors (urllib.error.HTTPError is an OSError) and
# truncated bodies (http.client.IncompleteRead is not an OSError).
TRANSIENT = (OSError, http.client.HTTPException)


class HttpRangeFile(io.RawIOBase):
    """Read-only, seekable file object backed by HTTP Range requests."""

    def __init__(self, url: str) -> None:
        super().__init__()
        self.origin = url
        self.url = url
        self.size = 0
        self.pos = 0
        self.bytes_fetched = 0
        self.requests = 0
        self._resolve()

    def _resolve(self) -> None:
        """Follow redirects once (release URL -> signed CDN URL) and read the size."""
        for attempt in range(ATTEMPTS):
            try:
                req = urllib.request.Request(self.origin, method="HEAD")
                with urllib.request.urlopen(req, timeout=60) as resp:
                    self.url = resp.geturl()
                    self.size = int(resp.headers["Content-Length"])
                    if resp.headers.get("Accept-Ranges", "").lower() != "bytes":
                        print("warning: server did not advertise Accept-Ranges: bytes", file=sys.stderr)
                return
            except TRANSIENT:
                if attempt == ATTEMPTS - 1:
                    raise
                time.sleep(2**attempt)

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_SET:
            self.pos = offset
        elif whence == io.SEEK_CUR:
            self.pos += offset
        elif whence == io.SEEK_END:
            self.pos = self.size + offset
        else:
            raise ValueError("bad whence")
        return self.pos

    def read(self, n: int = -1) -> bytes:
        if self.pos >= self.size:
            return b""
        end = self.size - 1 if n is None or n < 0 else min(self.size, self.pos + n) - 1
        want = end - self.pos + 1
        for attempt in range(ATTEMPTS):
            try:
                req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
                with urllib.request.urlopen(req, timeout=120) as resp:
                    if resp.status != 206:
                        raise IOError(f"expected 206 Partial Content, got {resp.status}")
                    data = resp.read()
                if len(data) != want:
                    raise IOError(f"short range read: wanted {want} bytes, got {len(data)}")
                break
            except TRANSIENT:
                if attempt == ATTEMPTS - 1:
                    raise
                time.sleep(2**attempt)
                # The signed CDN URL can expire mid-run; resolve the original URL again.
                self._resolve()
        self.requests += 1
        self.bytes_fetched += len(data)
        self.pos += len(data)
        return data

    def readinto(self, b) -> int:
        data = self.read(len(b))
        b[: len(data)] = data
        return len(data)


def run(cmd: str, url: str, rest: list) -> int:
    raw = HttpRangeFile(url)
    # A buffer keeps zipfile's many small reads from becoming many tiny HTTP requests.
    f = io.BufferedReader(raw, buffer_size=256 * 1024)
    with zipfile.ZipFile(f) as zf:
        if cmd == "list":
            for info in zf.infolist():
                print(f"{info.file_size:>12} {info.compress_size:>12} {info.filename}")
        else:
            dest, members = rest[0], rest[1:]
            os.makedirs(dest, exist_ok=True)
            for name in members:
                info = zf.getinfo(name)  # KeyError if missing -> reported, exit 1
                out = os.path.join(dest, os.path.basename(name))
                part = out + ".part"
                # Write beside the target and rename, so an interrupted run never leaves a
                # truncated file under the real name.
                with zf.open(info) as src, open(part, "wb") as dst:
                    while chunk := src.read(1024 * 1024):
                        dst.write(chunk)
                os.replace(part, out)
                print(f"extracted {name} -> {out} ({info.file_size} bytes, CRC checked)")
    print(
        f"archive size {raw.size} bytes; fetched {raw.bytes_fetched} bytes in {raw.requests} range requests",
        file=sys.stderr,
    )
    return 0


def main() -> int:
    args = sys.argv[1:]
    if len(args) < 2 or args[0] not in ("list", "extract") or (args[0] == "extract" and len(args) < 4):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        return run(args[0], args[1], args[2:])
    except TRANSIENT + (zipfile.BadZipFile, KeyError) as err:
        print(f"remote_zip: error: {err!r}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
