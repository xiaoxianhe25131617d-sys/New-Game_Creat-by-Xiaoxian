#!/usr/bin/env python3
"""Build silhouette-matched building pairs and low town foliage variants."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
HOUSES = ROOT / "assets" / "houses"
TOWN = ROOT / "assets" / "town"


def load_rgba(path: Path) -> Image.Image:
	return Image.open(path).convert("RGBA")


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
	bbox = image.getchannel("A").getbbox()
	if bbox is None:
		raise ValueError(f"{image} has no visible pixels")
	return bbox


def fit_visible_to_bbox(source: Image.Image, canvas_size: tuple[int, int], target_bbox: tuple[int, int, int, int]) -> Image.Image:
	crop = source.crop(alpha_bbox(source))
	target_w = target_bbox[2] - target_bbox[0]
	target_h = target_bbox[3] - target_bbox[1]
	resized = crop.resize((target_w, target_h), Image.Resampling.LANCZOS)
	canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
	canvas.alpha_composite(resized, (target_bbox[0], target_bbox[1]))
	return canvas


def apply_exact_alpha(image: Image.Image, alpha: Image.Image) -> Image.Image:
	result = image.copy()
	result.putalpha(alpha)
	return result


def add_closed_factory_door(front: Image.Image) -> Image.Image:
	result = front.copy()
	door = Image.new("RGBA", result.size, (0, 0, 0, 0))
	draw = ImageDraw.Draw(door)
	x0, y0, x1, y1 = 510, 614, 1005, 963
	draw.rectangle((x0, y0, x1, y1), fill=(45, 50, 50, 255))
	for y in range(y0 + 8, y1, 15):
		draw.line((x0, y, x1, y), fill=(18, 23, 25, 255), width=4)
		draw.line((x0, y + 4, x1, y + 4), fill=(82, 78, 65, 210), width=2)
	for x in (x0 + 10, x1 - 10):
		draw.line((x, y0, x, y1), fill=(22, 28, 30, 255), width=7)
	for x in range(x0 + 34, x1 - 20, 54):
		for y in range(y0 + 25, y1 - 10, 45):
			draw.ellipse((x, y, x + 5, y + 5), fill=(127, 103, 70, 220))
	draw.rectangle((x0, y1 - 25, x1, y1), fill=(38, 42, 41, 255))
	for x in range(x0, x1, 40):
		draw.polygon(((x, y1 - 25), (x + 20, y1 - 25), (x + 40, y1), (x + 20, y1)), fill=(179, 130, 43, 255))
	result.alpha_composite(door)
	return result


def color_grade(image: Image.Image, tint: tuple[int, int, int], amount: float, saturation: float) -> Image.Image:
	alpha = image.getchannel("A")
	rgb = ImageEnhance.Color(image.convert("RGB")).enhance(saturation)
	overlay = Image.new("RGB", image.size, tint)
	rgb = Image.blend(rgb, overlay, amount)
	result = rgb.convert("RGBA")
	result.putalpha(alpha)
	return result


def add_dance_hall_emblem(image: Image.Image) -> Image.Image:
	result = image.copy()
	alpha = result.getchannel("A")
	draw = ImageDraw.Draw(result)
	ink = (48, 28, 31, 255)
	draw.line((181, 653, 181, 752), fill=ink, width=15)
	draw.line((181, 653, 226, 638), fill=ink, width=15)
	draw.line((226, 638, 226, 714), fill=ink, width=13)
	draw.ellipse((139, 732, 188, 774), fill=ink)
	draw.ellipse((190, 696, 232, 734), fill=ink)
	result.putalpha(alpha)
	return result


def build_pair(front: Image.Image, back: Image.Image) -> tuple[Image.Image, Image.Image]:
	if back.size != front.size:
		back = fit_visible_to_bbox(back, front.size, alpha_bbox(front))
	else:
		back = fit_visible_to_bbox(back, front.size, alpha_bbox(front))
	mask = front.getchannel("A")
	return apply_exact_alpha(front, mask), apply_exact_alpha(back, mask)


def save_pair(prefix: str, front: Image.Image, back: Image.Image) -> None:
	front.save(HOUSES / f"{prefix}_front.png", optimize=True)
	back.save(HOUSES / f"{prefix}_back.png", optimize=True)


def build_buildings() -> None:
	house_front = load_rgba(HOUSES / "puzzle_house_front.png")
	house_back = load_rgba(HOUSES / "puzzle_house_back.png")
	house_front, house_back = build_pair(house_front, house_back)
	save_pair("puzzle_house_matched", house_front, house_back)

	dance_front = add_dance_hall_emblem(color_grade(house_front, (112, 55, 50), 0.10, 0.92))
	dance_back = color_grade(house_back, (139, 75, 45), 0.08, 0.95)
	save_pair("old_dance_hall", dance_front, dance_back)

	factory_front = add_closed_factory_door(load_rgba(HOUSES / "lightboard_factory_front.png"))
	factory_back = load_rgba(HOUSES / "lightboard_factory_back.png")
	factory_front, factory_back = build_pair(factory_front, factory_back)
	save_pair("lightboard_factory_matched", factory_front, factory_back)

	workshop_front = color_grade(factory_front, (49, 78, 81), 0.12, 0.78)
	workshop_back = color_grade(factory_back, (47, 74, 77), 0.10, 0.82)
	save_pair("dam_workshop", workshop_front, workshop_back)


def build_foliage() -> None:
	line = load_rgba(TOWN / "town_distant_tree_line.png")
	regions = [
		(15, 220, 395, 540),
		(330, 220, 745, 540),
		(700, 220, 1120, 540),
		(1060, 220, 1510, 540),
		(1450, 220, 1975, 540),
	]
	for index, region in enumerate(regions, start=1):
		crop = line.crop(region)
		visible = alpha_bbox(crop)
		crop = crop.crop((visible[0], visible[1], visible[2], visible[3]))
		crop.save(TOWN / f"foreground_cluster_{index:02d}.png", optimize=True)


def main() -> None:
	build_buildings()
	build_foliage()


if __name__ == "__main__":
	main()
