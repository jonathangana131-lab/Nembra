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
    if result["variantPixels"] != 0:
        raise SystemExit(f"status bar leaked into app-content evidence: {result}")

    blank_white = temp / "blank-white.png"
    blank_white.write_bytes(rgba_png(width, height, lambda _x, _y: (255, 255, 255, 255)))
    result = guard.inspect_rendered_content(blank_white)
    if result["ready"] or result["variantPixels"] != 0:
        raise SystemExit(f"blank white app content must fail closed: {result}")

    blank_transition = temp / "blank-white-system-chrome.png"

    def blank_transition_pixel(_x: int, y: int) -> tuple[int, int, int, int]:
        if height - 16 <= y < height:
            return (174, 174, 174, 255)
        return (255, 255, 255, 255)

    blank_transition.write_bytes(rgba_png(width, height, blank_transition_pixel))
    result = guard.inspect_rendered_content(blank_transition)
    if result["variantPixels"] < result["requiredVariantPixels"]:
        raise SystemExit(f"blank transition fixture did not exercise the vertical-band guard: {result}")
    if result["activeVerticalBands"] >= guard.MIN_ACTIVE_BANDS:
        raise SystemExit(f"blank transition fixture unexpectedly spans product-content bands: {result}")
    if result["ready"]:
        raise SystemExit(f"blank white transition with system chrome must fail closed: {result}")

    transparent_noise = temp / "transparent-hidden-rgb.png"

    def transparent_noise_pixel(x: int, y: int) -> tuple[int, int, int, int]:
        if y < status_bar_end:
            return (255, 255, 255, 255)
        if status_bar_end + 16 <= y < status_bar_end + 32:
            return ((x * 37) & 0xFF, (x * 17) & 0xFF, 220, 0)
        if status_bar_end + 112 <= y < status_bar_end + 128:
            return (40, (x * 29) & 0xFF, (x * 11) & 0xFF, 0)
        return (8, 8, 8, 0)

    transparent_noise.write_bytes(rgba_png(width, height, transparent_noise_pixel))
    try:
        guard.inspect_rendered_content(transparent_noise)
    except guard.PNGGuardError as exc:
        if "fully opaque" not in str(exc):
            raise SystemExit(f"transparent hidden-RGB evidence failed for the wrong reason: {exc}")
    else:
        raise SystemExit("fully transparent hidden RGB must never count as rendered app content")

    partially_transparent = temp / "partially-transparent-blank.png"

    def partially_transparent_pixel(_x: int, y: int) -> tuple[int, int, int, int]:
        if status_bar_end + 16 <= y < status_bar_end + 32:
            return (24, 24, 24, 128)
        if status_bar_end + 112 <= y < status_bar_end + 128:
            return (80, 80, 80, 1)
        return (250, 250, 250, 255)

    partially_transparent.write_bytes(rgba_png(width, height, partially_transparent_pixel))
    try:
        guard.inspect_rendered_content(partially_transparent)
    except guard.PNGGuardError as exc:
        if "fully opaque" not in str(exc):
            raise SystemExit(f"partially transparent evidence failed for the wrong reason: {exc}")
    else:
        raise SystemExit("partially transparent RGB variation must never prove rendered app content")

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
        raise SystemExit(f"non-trivial dark rendered app content should pass readiness: {result}")
    if result.get("alphaPolicy") != "rgba-app-region-fully-opaque":
        raise SystemExit(f"opaque RGBA readiness must retain explicit alpha policy: {result}")
    if result["activeVerticalBands"] < guard.MIN_ACTIVE_BANDS:
        raise SystemExit(f"dark rendered proof did not span required app-content bands: {result}")

    light_rendered = temp / "light-rendered.png"

    def light_rendered_pixel(_x: int, y: int) -> tuple[int, int, int, int]:
        if status_bar_end + 16 <= y < status_bar_end + 32:
            return (24, 24, 24, 255)
        if status_bar_end + 112 <= y < status_bar_end + 128:
            return (80, 80, 80, 255)
        return (250, 250, 250, 255)

    light_rendered.write_bytes(rgba_png(width, height, light_rendered_pixel))
    result = guard.inspect_rendered_content(light_rendered)
    if not result["ready"]:
        raise SystemExit(f"non-trivial light rendered app content should pass readiness: {result}")

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