#!/usr/bin/env python3
"""
Patch an existing Aurorae decoration.svg by adding theme-aware inner borders.

The original decoration, titlebar, buttons, shadows and geometry are preserved.
Only the optional Aurorae innerborder / innerborder-inactive FrameSvg elements
are replaced.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

ACTIVE_IDS = [
    "innerborder-topleft",
    "innerborder-top",
    "innerborder-topright",
    "innerborder-left",
    "innerborder-center",
    "innerborder-right",
    "innerborder-bottomleft",
    "innerborder-bottom",
    "innerborder-bottomright",
]

INACTIVE_IDS = [name.replace("innerborder-", "innerborder-inactive-") for name in ACTIVE_IDS]

def q(tag: str) -> str:
    return f"{{{SVG_NS}}}{tag}"

def remove_existing(root: ET.Element) -> None:
    wanted = set(ACTIVE_IDS + INACTIVE_IDS)
    for parent in root.iter():
        for child in list(parent):
            if child.attrib.get("id") in wanted:
                parent.remove(child)

def ensure_color_scheme_style(root: ET.Element) -> None:
    for elem in root.iter():
        if elem.tag == q("style") and elem.attrib.get("id") == "current-color-scheme":
            return

    style = ET.Element(q("style"), {
        "id": "current-color-scheme",
        "type": "text/css",
    })
    style.text = """
        .ColorScheme-Highlight { color: #3daee9; }
        .ColorScheme-Text { color: #232629; }
    """
    root.insert(0, style)

def rect(root: ET.Element, ident: str, x: int, y: int, w: int, h: int,
         css_class: str, opacity: float | None = None, transparent: bool = False) -> None:
    attrs = {
        "id": ident,
        "x": str(x),
        "y": str(y),
        "width": str(w),
        "height": str(h),
        "class": css_class,
    }

    if transparent:
        attrs["fill"] = "none"
        attrs["opacity"] = "0"
    else:
        attrs["fill"] = "currentColor"

    if opacity is not None:
        attrs["opacity"] = str(opacity)

    ET.SubElement(root, q("rect"), attrs)

def add_frame(root: ET.Element, prefix: str, x0: int, y0: int,
              thickness: int, css_class: str, opacity: float | None) -> None:
    span = 24
    t = thickness

    rect(root, f"{prefix}-topleft", x0, y0, t, t, css_class, opacity)
    rect(root, f"{prefix}-top", x0 + t + 2, y0, span, t, css_class, opacity)
    rect(root, f"{prefix}-topright", x0 + span + t + 4, y0, t, t, css_class, opacity)

    rect(root, f"{prefix}-left", x0, y0 + t + 2, t, span, css_class, opacity)
    rect(root, f"{prefix}-center", x0 + t + 2, y0 + t + 2, span, span,
         css_class, transparent=True)
    rect(root, f"{prefix}-right", x0 + span + t + 4, y0 + t + 2, t, span,
         css_class, opacity)

    rect(root, f"{prefix}-bottomleft", x0, y0 + span + t + 4, t, t, css_class, opacity)
    rect(root, f"{prefix}-bottom", x0 + t + 2, y0 + span + t + 4, span, t,
         css_class, opacity)
    rect(root, f"{prefix}-bottomright", x0 + span + t + 4,
         y0 + span + t + 4, t, t, css_class, opacity)

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Añade bordes innerborder a una decoración Aurorae existente."
    )
    parser.add_argument("svg", type=Path, help="Ruta a decoration.svg")
    parser.add_argument(
        "--active-width",
        type=int,
        default=4,
        help="Grosor del borde activo en píxeles SVG (predeterminado: 4)",
    )
    parser.add_argument(
        "--inactive-width",
        type=int,
        default=2,
        help="Grosor del borde inactivo en píxeles SVG (predeterminado: 2)",
    )
    parser.add_argument(
        "--inactive-opacity",
        type=float,
        default=0.42,
        help="Opacidad del borde inactivo entre 0 y 1 (predeterminado: 0.42)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = args.svg

    active_width = max(1, min(12, args.active_width))
    inactive_width = max(0, min(12, args.inactive_width))
    inactive_opacity = max(0.0, min(1.0, args.inactive_opacity))

    try:
        tree = ET.parse(path)
    except Exception as exc:
        print(f"No se pudo leer {path}: {exc}", file=sys.stderr)
        return 1

    root = tree.getroot()

    remove_existing(root)
    ensure_color_scheme_style(root)

    # Place the synthetic assets outside the original artwork. Aurorae resolves
    # them by SVG id, not by their absolute document position.
    add_frame(
        root,
        "innerborder",
        10000,
        10000,
        active_width,
        "ColorScheme-Highlight",
        None,
    )

    if inactive_width > 0:
        add_frame(
            root,
            "innerborder-inactive",
            10100,
            10000,
            inactive_width,
            "ColorScheme-Text",
            inactive_opacity,
        )

    tree.write(path, encoding="utf-8", xml_declaration=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
