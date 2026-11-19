# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools==4.68.0"]
# ///
"""Build and inspect the hand-drawn symbols in Artwork/InkIcons."""

import argparse
from collections import defaultdict
from dataclasses import dataclass
from html import escape
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
from urllib.parse import quote

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "Artwork/InkIcons"
CATALOG = ROOT / "NodeSeek/Assets.xcassets/InkIcons"
PREVIEW = ROOT / "build/icon-preview/index.html"
NS = "{http://www.w3.org/2000/svg}"
CONTENTS = '{"symbols":[{"filename":"symbol.svg","idiom":"universal"}],"info":{"author":"xcode","version":1}}\n'
# One hundred template units span the cap height. All three scales share an optical center.
SCALES = {"S": (495, 5.3), "M": (795, 6.6), "L": (1095, 7.5)}


@dataclass
class Drawing:
    title: str
    outline: str
    bounds: tuple

    @classmethod
    def read(cls, path):
        svg = ET.parse(path).getroot()
        title = svg.findtext(NS + "title", "").strip()
        outline = svg.find(NS + "path")
        if (svg.tag != NS + "svg" or svg.attrib != {"viewBox": "0 0 32 32"}
                or not title or outline is None or set(outline.attrib) != {"d"}
                or sorted(e.tag for e in svg) != sorted([NS + "title", NS + "path"])):
            raise ValueError(f"{path}: 原稿需要 32 × 32 的 viewBox、title 和一条已转为轮廓的 path。")
        pen = BoundsPen(None)
        data = outline.attrib["d"]
        parse_path(data, pen)
        if not pen.bounds:
            raise ValueError(f"{path}: 图标是空的。")
        x, y, right, bottom = pen.bounds
        if not (0 <= x < right <= 32 and 0 <= y < bottom <= 32):
            raise ValueError(f"{path}: 图形超出了 32 × 32 的画板或没有面积。")
        return cls(title, data, pen.bounds)


@dataclass
class Icon:
    path: Path
    drawing: Drawing
    variants: dict

    def symbol(self):
        guides, layers = [], []
        for size, (baseline, scale) in SCALES.items():
            drawing = self.variants.get(size, self.drawing)
            dx, dy = 69 - 16 * scale, -50 - 16 * scale
            x, _, right, _ = drawing.bounds
            for side, edge in (("left", dx + x * scale - 3), ("right", dx + right * scale + 3)):
                guides.append(f'    <path id="{side}-margin-Regular-{size}" d="M{1380+edge:.2f} {baseline-160}v220"/>')
            guides.append(f'    <path id="Baseline-{size}" d="M0 {baseline}h3300"/>')
            guides.append(f'    <path id="Capline-{size}" d="M0 {baseline-100}h3300"/>')
            pen = SVGPathPen(None, ntos=lambda n: f"{n:.3f}".rstrip("0").rstrip("."))
            parse_path(drawing.outline, TransformPen(pen, (scale, 0, 0, scale, dx, dy)))
            layers.append(f'    <g id="Regular-{size}" transform="translate(1380 {baseline})"><path d="{pen.getCommands()}"/></g>')
        return "\n".join(['<svg xmlns="http://www.w3.org/2000/svg" width="3300" height="2200" viewBox="0 0 3300 2200">',
                          '  <g id="Notes"><text id="template-version">Template v.5.0</text></g>',
                          '  <g id="Guides">', *guides, '  </g>',
                          '  <g id="Symbols">', *layers, '  </g>', '</svg>', ''])


def read_icons():
    icons, variants = {}, []
    for path in sorted(ART.rglob("*.svg")):
        match = re.fullmatch(r"(Ink[A-Z][a-zA-Z0-9]*)(?:-([SL]))?", path.stem)
        if len(path.relative_to(ART).parts) != 2 or not match:
            raise ValueError(f"{path}: 请按 场景/Ink用途.svg 命名，单独画的尺寸可加 -S 或 -L。")
        name, size = match.groups()
        if size:
            variants.append((name, size, path))
        elif name in icons:
            raise ValueError(f"{path} 和 {icons[name].path} 使用了同一个名字。")
        else:
            icons[name] = Icon(path, Drawing.read(path), {})
    for name, size, path in variants:
        if name not in icons or icons[name].path.parent != path.parent:
            raise ValueError(f"{path}: 同一目录缺少 {name}.svg。")
        icons[name].variants[size] = Drawing.read(path)
    if not icons:
        raise ValueError(f"{ART} 中没有图标。")
    return icons


def catalog(icons, check):
    expected = {CATALOG / icon.path.parent.name / (name + ".symbolset"): icon for name, icon in icons.items()}
    stale = set(CATALOG.rglob("*.symbolset")) - expected.keys()
    if stale:
        raise ValueError("以下资源已经没有对应原稿，请确认后移除：\n" + "\n".join(str(p.relative_to(ROOT)) for p in sorted(stale)))
    differences = []
    for directory, icon in expected.items():
        for filename, content in (("Contents.json", CONTENTS), ("symbol.svg", icon.symbol())):
            path = directory / filename
            if path.is_file() and path.read_bytes() == content.encode():
                continue
            if check:
                differences.append(str(path.relative_to(ROOT)))
            else:
                directory.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
    if differences:
        raise ValueError("以下资源需要重新生成：\n" + "\n".join(differences))


def preview(icons):
    defs, groups = [], defaultdict(list)
    for name, icon in icons.items():
        defs.append(f'<path id="{name}" d="{icon.drawing.outline}"/>')
        for size, drawing in icon.variants.items():
            defs.append(f'<path id="{name}-{size}" d="{drawing.outline}"/>')

    def glyph(name, size, points):
        icon = icons[name]
        drawing = icon.variants.get(size, icon.drawing)
        scale = SCALES[size][1]
        # Match the symbol guides to a system font's approximate cap height.
        units_per_em = 100 / (0.71 * scale)
        left, _, right, _ = drawing.bounds
        width = right - left + 6 / scale
        box = f"{left-3/scale:.5f} {16-units_per_em/2:.5f} {width:.5f} {units_per_em:.5f}"
        source = name + "-" + size if size in icon.variants else name
        return (f'<svg aria-hidden="true" viewBox="{box}" width="{points*width/units_per_em:.3f}" '
                f'height="{points}" fill="currentColor" overflow="visible"><use href="#{source}"/></svg>')

    for name, icon in icons.items():
        group = icon.path.parent.name
        ref = quote("../../" + icon.path.relative_to(ROOT).as_posix())
        title = escape(icon.drawing.title)
        groups[group].append(f'<a class="item" href="{ref}" data-key="{name}" title="{name}">'
                             + "".join(f'<span class="size-{s}">{glyph(name, s, pt)}</span>' for s, pt in zip("SML", (12, 17, 24)))
                             + f'<span>{title}</span></a>')
    sections = "".join(f'<section class="group"><h2>{escape(title)}</h2><div class="grid">{"".join(items)}</div></section>'
                       for title, items in groups.items())
    template = Path(__file__).with_name("preview.html").read_text(encoding="utf-8")
    template = re.sub(r"\{\{(Ink[A-Za-z0-9]+) ([SML]) (\d+)\}\}",
                      lambda m: glyph(m[1], m[2], int(m[3])), template)
    page = template.replace("{{defs}}", "".join(defs)).replace("{{sections}}", sections)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW.write_text(page, encoding="utf-8")
    print(PREVIEW)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("generate", "check", "preview"))
    action = parser.parse_args().action
    try:
        library = read_icons()
        if action == "preview":
            preview(library)
        else:
            catalog(library, check=action == "check")
            print(f"{len(library)} 个图标，三个尺寸均已{'检查' if action == 'check' else '生成'}。")
    except (ValueError, ET.ParseError, OSError) as error:
        sys.exit(str(error))
