from pathlib import Path
import importlib.util
import struct
import tempfile
import zlib

root = Path(__file__).resolve().parents[3]
guard_path = root / "scripts/ci/capture_visual_png_content_guard.py"
spec = importlib.util.spec_from_file_location("capture_visual_png_content_guard", guard_path)
if spec is None or spec.loader is None:
    raise SystemExit("could not load Capture PNG content guard")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def chunk(kind: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(kind)
    crc = zlib.crc32(payload, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def rgba_png(width: int, height: int, pixel) -> bytes:
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            r, g, b, a = pixel(x, y)
            rows.extend((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return guard.PNG_SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b"")


with tempfile.TemporaryDirectory() as temp_dir:
    temp = Path(temp_dir)
    width, height = 128, 256
    status_bar_end = height // 8

    status_only = temp / "status-only.png"
    status_only.write_bytes(rgba_png(width, height, lambda _x, y: (255, 255, 255, 255) if y < status_bar_end else (0, 0, 0, 255)))
    result = guard.inspect_rendered_content(status_only)
    if result["ready"]:
        raise SystemExit(f"status-bar-only screenshot must fail closed: {result}")
    if result["nonDarkPixels"] != 0:
        raise SystemExit(f"status bar leaked into app-content evidence: {result}")

    rendered = temp / "rendered.png"

    def rendered_pixel(_x: int, y: int) -> tuple[int, int, int, int]:
        if status_bar_end + 16 <= y < status_bar_end + 32:
            return (220, 220, 220, 255)
        if status_bar_end + 112 <= y < status_bar_end + 128:
            return (180, 180, 180, 255)
        return (8, 8, 8, 255)

    rendered.write_bytes(rgba_png(width, height, rendered_pixel))
    result = guard.inspect_rendered_content(rendered)
    if not result["ready"]:
        raise SystemExit(f"non-trivial rendered app content should pass readiness: {result}")
    if result["activeVerticalBands"] < guard.MIN_ACTIVE_BANDS:
        raise SystemExit(f"rendered proof did not span required app-content bands: {result}")

    corrupted = bytearray(rendered.read_bytes())
    corrupted[-5] ^= 0x01
    corrupted_path = temp / "corrupted.png"
    corrupted_path.write_bytes(corrupted)
    try:
        guard.inspect_rendered_content(corrupted_path)
    except guard.PNGGuardError:
        pass
    else:
        raise SystemExit("corrupted PNG evidence must fail closed")

print("capture visual PNG rendered-content guard: PASS")