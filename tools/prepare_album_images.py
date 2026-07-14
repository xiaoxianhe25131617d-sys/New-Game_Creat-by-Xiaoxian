from pathlib import Path
import sys

from PIL import Image, ImageEnhance, ImageFilter


TARGET_SIZE = 1026


def prepare(source_path: Path, output_path: Path, remove_label: bool = False) -> None:
    image = Image.open(source_path).convert("RGB")
    if remove_label:
        # The first source has a label in the upper-left sky. Cropping below it
        # keeps all four children and avoids painting over the original art.
        crop_top = min(80, image.height // 8)
        image = image.crop((0, crop_top, image.width, image.height))

    background = image.copy()
    scale = max(TARGET_SIZE / background.width, TARGET_SIZE / background.height)
    background = background.resize(
        (round(background.width * scale), round(background.height * scale)),
        Image.Resampling.LANCZOS,
    )
    left = (background.width - TARGET_SIZE) // 2
    top = (background.height - TARGET_SIZE) // 2
    background = background.crop((left, top, left + TARGET_SIZE, top + TARGET_SIZE))
    background = background.filter(ImageFilter.GaussianBlur(22))
    background = ImageEnhance.Brightness(background).enhance(0.82)

    foreground = image.copy()
    foreground.thumbnail((TARGET_SIZE, TARGET_SIZE), Image.Resampling.LANCZOS)
    foreground = ImageEnhance.Color(foreground).enhance(0.96)
    foreground = ImageEnhance.Contrast(foreground).enhance(1.02)
    paste_x = (TARGET_SIZE - foreground.width) // 2
    paste_y = (TARGET_SIZE - foreground.height) // 2
    background.paste(foreground, (paste_x, paste_y))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    background.save(output_path, format="PNG", optimize=True)


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit("usage: prepare_album_images.py image1 image2 image3 output_dir")
    output_dir = Path(sys.argv[4])
    for index, source in enumerate(sys.argv[1:4], start=1):
        prepare(Path(source), output_dir / f"friends_{index:02d}.png", index == 1)


if __name__ == "__main__":
    main()
