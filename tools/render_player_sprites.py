"""Prepare the protagonist sprite sheets from an NPC-style generated source.

The source is an eight-pose, one-row image.  This tool removes the generated
checkerboard, keeps the eight largest character components, and places them
on identical 96x128 cells with a shared grounded baseline.  The underground
variant adds only a helmet and head lamp; the body poses remain identical.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


CELL_SIZE = (96, 128)
GROUND_Y = 123


def is_checkerboard(rgb: tuple[int, int, int]) -> bool:
    """Recognize the pale, low-saturation generated transparency grid."""

    return min(rgb) >= 220 and max(rgb) - min(rgb) <= 24


def find_character_components(image: Image.Image) -> list[set[tuple[int, int]]]:
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    mask = [[not is_checkerboard(pixels[x, y]) for x in range(width)] for y in range(height)]
    visited: set[tuple[int, int]] = set()
    components: list[set[tuple[int, int]]] = []

    for y in range(height):
        for x in range(width):
            if not mask[y][x] or (x, y) in visited:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited.add((x, y))
            component: set[tuple[int, int]] = set()
            while queue:
                px, py = queue.popleft()
                component.add((px, py))
                for nx, ny in ((px + 1, py), (px - 1, py), (px, py + 1), (px, py - 1)):
                    if 0 <= nx < width and 0 <= ny < height and mask[ny][nx] and (nx, ny) not in visited:
                        visited.add((nx, ny))
                        queue.append((nx, ny))
            if len(component) > 500:
                components.append(component)

    if len(components) != 8:
        raise RuntimeError(f"Expected 8 character components, found {len(components)}")
    return sorted(components, key=lambda points: min(x for x, _ in points))


def component_frame(source: Image.Image, component: set[tuple[int, int]]) -> Image.Image:
    min_x = min(x for x, _ in component)
    min_y = min(y for _, y in component)
    max_x = max(x for x, _ in component) + 1
    max_y = max(y for _, y in component) + 1
    crop = source.crop((min_x, min_y, max_x, max_y)).convert("RGBA")
    alpha = Image.new("L", crop.size, 0)
    alpha_pixels = alpha.load()
    for x, y in component:
        alpha_pixels[x - min_x, y - min_y] = 255
    crop.putalpha(alpha)

    target_height = 112
    scale = target_height / crop.height
    scaled = crop.resize((max(1, round(crop.width * scale)), target_height), Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", CELL_SIZE, (0, 0, 0, 0))
    x = (CELL_SIZE[0] - scaled.width) // 2
    y = GROUND_Y - scaled.height
    cell.alpha_composite(scaled, (x, y))
    return cell


def add_underground_gear(cell: Image.Image) -> Image.Image:
    result = cell.copy()
    alpha = result.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        return result

    left, top, right, _ = bbox
    center = (left + right) // 2
    draw = ImageDraw.Draw(result)
    outline = (40, 35, 38, 255)
    helmet = (76, 78, 83, 255)
    helmet_shadow = (49, 51, 57, 255)
    lamp = (255, 226, 126, 255)

    # Keep the face and body untouched: only add the small underground kit.
    draw.polygon(
        [(center - 16, top + 10), (center - 12, top + 2), (center - 5, top - 2),
         (center + 8, top - 2), (center + 15, top + 3), (center + 18, top + 10)],
        fill=outline,
    )
    draw.polygon(
        [(center - 12, top + 8), (center - 9, top + 3), (center + 7, top + 2),
         (center + 13, top + 7), (center + 14, top + 10), (center - 13, top + 10)],
        fill=helmet,
    )
    draw.rectangle((center - 8, top + 3, center + 6, top + 5), fill=helmet_shadow)
    draw.rectangle((center - 3, top - 5, center + 4, top + 2), fill=outline)
    draw.rectangle((center - 2, top - 4, center + 3, top + 1), fill=lamp)
    draw.point((center, top - 3), fill=(255, 251, 205, 255))
    return result


def write_sheets(source_path: Path, normal_path: Path, underground_path: Path) -> None:
    source = Image.open(source_path).convert("RGB")
    components = find_character_components(source)
    frames = [component_frame(source, component) for component in components]

    normal = Image.new("RGBA", (CELL_SIZE[0] * 8, CELL_SIZE[1]), (0, 0, 0, 0))
    underground = Image.new("RGBA", normal.size, (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        normal.alpha_composite(frame, (index * CELL_SIZE[0], 0))
        underground.alpha_composite(add_underground_gear(frame), (index * CELL_SIZE[0], 0))

    normal_path.parent.mkdir(parents=True, exist_ok=True)
    underground_path.parent.mkdir(parents=True, exist_ok=True)
    normal.save(normal_path, "PNG", optimize=True)
    underground.save(underground_path, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="NPC-style generated eight-pose source PNG")
    parser.add_argument("normal", type=Path)
    parser.add_argument("underground", type=Path)
    args = parser.parse_args()
    write_sheets(args.source, args.normal, args.underground)


if __name__ == "__main__":
    main()
