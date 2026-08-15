#!/usr/bin/env python3
"""Fail-closed rendered-content guard for Capture Simulator screenshots.

This is intentionally not an aesthetic oracle. It only proves that the app-content
region contains non-trivial rendered pixels before a screenshot is admitted into
the visual-review artifact. Human screenshot review remains required.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import sys
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_PIXELS = 20_000_000
COLOR_BUCKET_SHIFT = 4
CONTENT_FRACTION_DENOMINATOR = 500
MIN_CONTENT_PIXELS = 1_024
VERTICAL_BANDS = 4
MIN_ACTIVE_BANDS = 2


class PNGGuardError(ValueError):
    pass


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


def _parse_png(path: Path) -> tuple[int, int, int, bytes]:
    payload = path.read_bytes()
    if not payload.startswith(PNG_SIGNATURE):
        raise PNGGuardError("missing PNG signature")
    offset = len(PNG_SIGNATURE)
    width = height = color_type = None
    idat = bytearray()
    saw_ihdr = False
    saw_iend = False
    while offset < len(payload):
        if offset + 12 > len(payload):
            raise PNGGuardError("truncated PNG chunk")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_type = payload[offset + 4 : offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        crc_end = data_end + 4
        if crc_end > len(payload):
            raise PNGGuardError("truncated PNG chunk payload")
        chunk_data = payload[data_start:data_end]
        expected_crc = struct.unpack(">I", payload[data_end:crc_end])[0]
        actual_crc = zlib.crc32(chunk_type)
        actual_crc = zlib.crc32(chunk_data, actual_crc) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise PNGGuardError(f"CRC mismatch in {chunk_type!r}")
        if chunk_type == b"IHDR":
            if saw_ihdr or length != 13:
                raise PNGGuardError("invalid IHDR")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk_data)
            if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
                raise PNGGuardError("unsupported screenshot dimensions")
            if bit_depth != 8 or color_type not in (2, 6):
                raise PNGGuardError("expected 8-bit RGB/RGBA Simulator PNG")
            if compression != 0 or filtering != 0 or interlace != 0:
                raise PNGGuardError("unsupported PNG compression/filter/interlace mode")
            saw_ihdr = True
        elif chunk_type == b"IDAT":
            if not saw_ihdr:
                raise PNGGuardError("IDAT before IHDR")
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            if length != 0:
                raise PNGGuardError("invalid IEND")
            saw_iend = True
            offset = crc_end
            break
        offset = crc_end
    if not saw_ihdr or not saw_iend or not idat:
        raise PNGGuardError("incomplete PNG")
    if offset != len(payload):
        raise PNGGuardError("trailing bytes after IEND")
    assert width is not None and height is not None and color_type is not None
    return width, height, color_type, bytes(idat)


def _color_bucket(r: int, g: int, b: int) -> tuple[int, int, int]:
    return (r >> COLOR_BUCKET_SHIFT, g >> COLOR_BUCKET_SHIFT, b >> COLOR_BUCKET_SHIFT)


def inspect_rendered_content(path: Path) -> dict[str, object]:
    width, height, color_type, compressed = _parse_png(path)
    bytes_per_pixel = 4 if color_type == 6 else 3
    stride = width * bytes_per_pixel
    expected_size = height * (stride + 1)
    decompressor = zlib.decompressobj()
    raw = decompressor.decompress(compressed, expected_size + 1)
    raw += decompressor.flush()
    if len(raw) != expected_size or decompressor.unused_data or decompressor.unconsumed_tail:
        raise PNGGuardError("unexpected decompressed PNG size")
    app_y_start = max(1, height // 8)
    app_rows = height - app_y_start
    if app_rows <= 0:
        raise PNGGuardError("screenshot has no app-content region")
    previous = bytearray(stride)
    cursor = 0
    color_counts: dict[tuple[int, int, int], int] = {}
    band_color_counts: list[dict[tuple[int, int, int], int]] = [dict() for _ in range(VERTICAL_BANDS)]
    band_pixel_counts = [0] * VERTICAL_BANDS
    for y in range(height):
        filter_type = raw[cursor]
        cursor += 1
        encoded = raw[cursor : cursor + stride]
        cursor += stride
        reconstructed = bytearray(stride)
        for i, value in enumerate(encoded):
            left = reconstructed[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
            up = previous[i]
            up_left = previous[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
            if filter_type == 0:
                decoded = value
            elif filter_type == 1:
                decoded = (value + left) & 0xFF
            elif filter_type == 2:
                decoded = (value + up) & 0xFF
            elif filter_type == 3:
                decoded = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                decoded = (value + _paeth(left, up, up_left)) & 0xFF
            else:
                raise PNGGuardError(f"unsupported PNG row filter {filter_type}")
            reconstructed[i] = decoded
        if y >= app_y_start:
            band = min(VERTICAL_BANDS - 1, ((y - app_y_start) * VERTICAL_BANDS) // app_rows)
            for x in range(0, stride, bytes_per_pixel):
                if color_type == 6 and reconstructed[x + 3] != 255:
                    raise PNGGuardError(
                        "RGBA app-content pixel is not fully opaque; hidden RGB cannot prove rendered content"
                    )
                bucket = _color_bucket(reconstructed[x], reconstructed[x + 1], reconstructed[x + 2])
                color_counts[bucket] = color_counts.get(bucket, 0) + 1
                band_counts = band_color_counts[band]
                band_counts[bucket] = band_counts.get(bucket, 0) + 1
                band_pixel_counts[band] += 1
        previous = reconstructed
    app_pixels = width * app_rows
    if not color_counts or sum(color_counts.values()) != app_pixels:
        raise PNGGuardError("could not classify app-content pixels")
    dominant_bucket, dominant_pixels = max(color_counts.items(), key=lambda item: item[1])
    variant_pixels = app_pixels - dominant_pixels
    band_variant_pixels = [
        band_pixel_counts[index] - band_color_counts[index].get(dominant_bucket, 0)
        for index in range(VERTICAL_BANDS)
    ]
    required_pixels = max(MIN_CONTENT_PIXELS, app_pixels // CONTENT_FRACTION_DENOMINATOR)
    band_pixels = width * max(1, app_rows // VERTICAL_BANDS)
    required_band_pixels = max(64, band_pixels // 5_000)
    active_bands = sum(count >= required_band_pixels for count in band_variant_pixels)
    ready = variant_pixels >= required_pixels and active_bands >= MIN_ACTIVE_BANDS
    return {
        "width": width,
        "height": height,
        "appYStart": app_y_start,
        "dominantColorBucketRGB4": list(dominant_bucket),
        "dominantColorPixels": dominant_pixels,
        "variantPixels": variant_pixels,
        "requiredVariantPixels": required_pixels,
        "activeVerticalBands": active_bands,
        "requiredActiveVerticalBands": MIN_ACTIVE_BANDS,
        "bandVariantPixels": band_variant_pixels,
        "alphaPolicy": "rgba-app-region-fully-opaque" if color_type == 6 else "implicit-opaque-rgb",
        "ready": ready,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("png", type=Path)
    parser.add_argument("--label", default="Capture screenshot")
    args = parser.parse_args()
    try:
        result = inspect_rendered_content(args.png)
    except (OSError, PNGGuardError, zlib.error) as exc:
        print(f"{args.label}: invalid visual evidence: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, sort_keys=True))
    if not result["ready"]:
        print(f"{args.label}: app-content region is not visibly rendered; refusing blank/partial visual evidence", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())