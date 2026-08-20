#!/usr/bin/env python3
"""Fail closed when labeled light/dark Simulator captures do not render that appearance."""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _decode_rows(path: Path) -> tuple[int, int, int, list[bytes]]:
    blob = path.read_bytes()
    if not blob.startswith(PNG_SIGNATURE):
        raise ValueError(f"{path} is not a PNG")

    cursor = len(PNG_SIGNATURE)
    ihdr: tuple[int, int, int, int, int, int, int] | None = None
    compressed: list[bytes] = []
    while cursor < len(blob):
        if cursor + 12 > len(blob):
            raise ValueError(f"{path} has a truncated PNG chunk")
        length = struct.unpack(">I", blob[cursor : cursor + 4])[0]
        kind = blob[cursor + 4 : cursor + 8]
        data = blob[cursor + 8 : cursor + 8 + length]
        cursor += 12 + length
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", data)
        elif kind == b"IDAT":
            compressed.append(data)
        elif kind == b"IEND":
            break

    if ihdr is None or not compressed:
        raise ValueError(f"{path} is missing required PNG data")

    width, height, bit_depth, color_type, compression, filtering, interlace = ihdr
    if bit_depth != 8 or color_type not in (2, 6) or compression != 0 or filtering != 0 or interlace != 0:
        raise ValueError(
            f"{path} uses unsupported PNG encoding: bit_depth={bit_depth}, "
            f"color_type={color_type}, interlace={interlace}"
        )

    channels = 3 if color_type == 2 else 4
    stride = width * channels
    raw = zlib.decompress(b"".join(compressed))
    expected = height * (stride + 1)
    if len(raw) != expected:
        raise ValueError(f"{path} decoded byte count {len(raw)} != expected {expected}")

    rows: list[bytes] = []
    prior = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        scan = bytearray(raw[offset : offset + stride])
        offset += stride
        for index, encoded in enumerate(scan):
            left = scan[index - channels] if index >= channels else 0
            above = prior[index]
            upper_left = prior[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded = encoded
            elif filter_type == 1:
                decoded = encoded + left
            elif filter_type == 2:
                decoded = encoded + above
            elif filter_type == 3:
                decoded = encoded + ((left + above) // 2)
            elif filter_type == 4:
                decoded = encoded + _paeth(left, above, upper_left)
            else:
                raise ValueError(f"{path} uses unsupported PNG row filter {filter_type}")
            scan[index] = decoded & 0xFF
        rows.append(bytes(scan))
        prior = scan

    return width, height, channels, rows


def _corner_background_luminance(path: Path) -> float:
    width, height, channels, rows = _decode_rows(path)
    centers = (
        (max(1, int(width * 0.02)), max(1, int(height * 0.02))),
        (min(width - 2, int(width * 0.98)), max(1, int(height * 0.02))),
        (max(1, int(width * 0.02)), min(height - 2, int(height * 0.98))),
        (min(width - 2, int(width * 0.98)), min(height - 2, int(height * 0.98))),
    )

    values: list[float] = []
    radius = 8
    for center_x, center_y in centers:
        for y in range(max(0, center_y - radius), min(height, center_y + radius + 1)):
            row = rows[y]
            for x in range(max(0, center_x - radius), min(width, center_x + radius + 1)):
                index = x * channels
                red, green, blue = row[index : index + 3]
                values.append((0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0)

    if not values:
        raise ValueError(f"{path} produced no appearance samples")
    return sum(values) / len(values)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--light", type=Path, required=True)
    parser.add_argument("--dark", type=Path, required=True)
    parser.add_argument("--log", type=Path)
    args = parser.parse_args()

    light = _corner_background_luminance(args.light)
    dark = _corner_background_luminance(args.dark)
    report = f"light_corner_luminance={light:.4f}\ndark_corner_luminance={dark:.4f}\ndelta={light - dark:.4f}\n"
    sys.stdout.write(report)
    if args.log:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        args.log.write_text(report, encoding="utf-8")

    if light < 0.75:
        print("Invalid light-mode evidence: corner background is not light.", file=sys.stderr)
        return 10
    if dark > 0.35:
        print("Invalid dark-mode evidence: corner background is not dark.", file=sys.stderr)
        return 11
    if light - dark < 0.40:
        print("Invalid appearance evidence: rendered light/dark separation is too small.", file=sys.stderr)
        return 12
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, zlib.error, struct.error) as error:
        print(f"Appearance verification failed: {error}", file=sys.stderr)
        raise SystemExit(13)
