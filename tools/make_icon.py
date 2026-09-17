#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App 图标（1024x1024 PNG）。纯标准库实现，不依赖 PIL。"""
import math
import struct
import sys
import zlib

W = H = 1024
img = bytearray(W * H * 4)  # RGBA


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def over(x, y, r, g, b, a):
    """alpha 合成一个像素"""
    if a <= 0.0:
        return
    i = (y * W + x) * 4
    da = img[i + 3] / 255.0
    na = a + da * (1 - a)
    if na <= 0:
        return
    for k, c in enumerate((r, g, b)):
        dc = img[i + k]
        img[i + k] = int(round((c * a + dc * da * (1 - a)) / na))
    img[i + 3] = int(round(na * 255))


def sdf_round_rect(px, py, cx, cy, hw, hh, rad):
    qx = abs(px - cx) - (hw - rad)
    qy = abs(py - cy) - (hh - rad)
    ax = max(qx, 0.0)
    ay = max(qy, 0.0)
    return math.hypot(ax, ay) + min(max(qx, qy), 0.0) - rad


def sdf_circle(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def sdf_segment(px, py, x1, y1, x2, y2, half):
    dx, dy = x2 - x1, y2 - y1
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else clamp(((px - x1) * dx + (py - y1) * dy) / l2)
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy)) - half


def fill(bbox, sdf, color, alpha=1.0):
    x0, y0, x1, y1 = bbox
    for y in range(max(0, int(y0)), min(H, int(y1) + 1)):
        for x in range(max(0, int(x0)), min(W, int(x1) + 1)):
            d = sdf(x + 0.5, y + 0.5)
            cv = clamp(0.5 - d)
            if cv > 0:
                r, g, b = color
                over(x, y, r, g, b, cv * alpha)


# ---------- 背景：圆角方块 + 蓝→青渐变 ----------
TOP = (86, 143, 255)
BOTTOM = (20, 186, 168)


def bg_sdf(px, py):
    return sdf_round_rect(px, py, 512, 512, 512, 512, 232)


for y in range(H):
    t = y / (H - 1)
    col = tuple(TOP[k] + (BOTTOM[k] - TOP[k]) * t for k in range(3))
    for x in range(W):
        d = bg_sdf(x + 0.5, y + 0.5)
        cv = clamp(0.5 - d)
        if cv > 0:
            over(x, y, col[0], col[1], col[2], cv)

# ---------- 三条白色“存储条” ----------
bars = [
    (360, 250, 0.95),
    (494, 205, 0.80),
    (628, 160, 0.62),
]
for cy, hw, alpha in bars:
    fill((512 - hw - 4, cy - 48, 512 + hw + 4, cy + 48),
         lambda px, py, cy=cy, hw=hw: sdf_round_rect(px, py, 512, cy, hw, 44, 44),
         (255, 255, 255), alpha)

# ---------- 右下角“已完成”徽章 ----------
fill((768 - 160, 768 - 160, 768 + 160, 768 + 160),
     lambda px, py: sdf_circle(px, py, 768, 768, 152),
     (255, 255, 255), 1.0)

GREEN = (34, 197, 94)
fill((690, 680, 860, 830), lambda px, py: sdf_segment(px, py, 706, 772, 752, 818, 21), GREEN)
fill((730, 680, 870, 830), lambda px, py: sdf_segment(px, py, 752, 818, 834, 706, 21), GREEN)


def write_png(path):
    raw = bytearray()
    stride = W * 4
    for y in range(H):
        raw.append(0)  # filter: none
        raw += img[y * stride:(y + 1) * stride]
    comp = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", comp)
    out += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "icon_1024.png"
    write_png(target)
    print("icon written:", target)
