#!/usr/bin/env python3
"""
手绘叮咚 App 图标（不借助任何图片生成模型）。

设计语言：
  · 深靛→紫的夜空渐变 = 睡眠/休息
  · 金色铃铛 = 闹钟本体，也是 App 的主题色（AlarmKit tint 就是橙金）
  · 两侧的声波弧线 = 「叮咚」的铃声
  · 右上角的细月牙 = 休息日保持安静

技术：4 倍超采样画完再缩回 1024，边缘锐利无锯齿；输出不带 alpha 通道
（iOS 图标要求不透明、满幅方形，圆角由系统自己裁）。
"""
from PIL import Image, ImageDraw, ImageFilter
import math

SS = 4                 # 超采样倍数
OUT = 1024
S = OUT * SS           # 实际画布尺寸
CX = S // 2

def sc(v: float) -> float:
    """1024 坐标系 → 超采样坐标系"""
    return v * SS

# ---------------------------------------------------------------- 背景：垂直渐变
TOP = (0x2B, 0x25, 0x59)     # 深靛
BOT = (0x7A, 0x5B, 0xA8)     # 紫

img = Image.new("RGB", (S, S), TOP)
px = img.load()
for y in range(S):
    t = y / (S - 1)
    r = round(TOP[0] + (BOT[0] - TOP[0]) * t)
    g = round(TOP[1] + (BOT[1] - TOP[1]) * t)
    b = round(TOP[2] + (BOT[2] - TOP[2]) * t)
    for x in range(S):
        px[x, y] = (r, g, b)

draw = ImageDraw.Draw(img, "RGBA")

# ---------------------------------------------------------------- 铃铛背后的暖色光晕
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([sc(512 - 300), sc(400 - 280), sc(512 + 300), sc(400 + 280)],
           fill=(0xFF, 0xC4, 0x4D, 90))
glow = glow.filter(ImageFilter.GaussianBlur(sc(60)))
img = Image.alpha_composite(img.convert("RGBA"), glow)
draw = ImageDraw.Draw(img, "RGBA")

# ---------------------------------------------------------------- 金色渐变（铃铛用）
GOLD_TOP = (0xFF, 0xD1, 0x66)
GOLD_BOT = (0xF3, 0xA0, 0x1F)

def gold_at(t: float):
    t = max(0.0, min(1.0, t))
    return (round(GOLD_TOP[0] + (GOLD_BOT[0] - GOLD_TOP[0]) * t),
            round(GOLD_TOP[1] + (GOLD_BOT[1] - GOLD_TOP[1]) * t),
            round(GOLD_TOP[2] + (GOLD_BOT[2] - GOLD_TOP[2]) * t))

# ---------------------------------------------------------------- 两侧声波弧线（先画，被铃铛压在下面）
ARC_CX, ARC_CY = sc(512), sc(395)
for radius_1024, width_1024, alpha in ((330, 15, 150), (392, 11, 95)):
    r = sc(radius_1024)
    w = sc(width_1024)
    bbox = [ARC_CX - r, ARC_CY - r, ARC_CX + r, ARC_CY + r]
    # 右侧：-38° ~ 38°（PIL 角度以 3 点钟方向为 0，顺时针）
    draw.arc(bbox, start=-38, end=38, fill=(0xFF, 0xD1, 0x66, alpha), width=w)
    # 左侧：142° ~ 218°
    draw.arc(bbox, start=142, end=218, fill=(0xFF, 0xD1, 0x66, alpha), width=w)

# ---------------------------------------------------------------- 铃铛主体
# 铃身：上缘全圆角的圆顶 + 下方拉直
DOME_L, DOME_T, DOME_R, DOME_B = sc(312), sc(195), sc(712), sc(600)
DOME_R_ADJ = (DOME_R - DOME_L) / 2          # 半宽 = 圆角半径 → 顶部是正半圆
draw.rounded_rectangle([DOME_L, DOME_T, DOME_R, DOME_B],
                       radius=DOME_R_ADJ, fill=gold_at(0.18))
# 把下半部分的圆角补成直角（与圆顶同色，视觉上就是「半圆顶 + 直筒」）
draw.rectangle([DOME_L, DOME_T + DOME_R_ADJ, DOME_R, DOME_B], fill=gold_at(0.18))

# 铃口沿：一条更宽的圆角横杆
RIM_L, RIM_T, RIM_R, RIM_B = sc(252), sc(642), sc(772), sc(734)
draw.rounded_rectangle([RIM_L, RIM_T, RIM_R, RIM_B], radius=sc(46), fill=gold_at(0.72))

# 铃舌：口沿下方的半圆
CL_L, CL_T, CL_R, CL_B = sc(432), sc(752), sc(592), sc(852)
draw.pieslice([CL_L, CL_T, CL_R, CL_B], start=0, end=180, fill=gold_at(1.0))

# ---------------------------------------------------------------- 右上角细月牙
moon_mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(moon_mask)
MX, MY, MR = sc(868), sc(96), sc(44)
md.ellipse([MX - MR, MY - MR, MX + MR, MY + MR], fill=255)
# 用一个偏移的同尺寸圆「挖」出月牙
OX, OY = sc(886), sc(80)
md.ellipse([OX - MR, OY - MR, OX + MR, OY + MR], fill=0)

moon_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
moon_layer.putalpha(moon_mask)
# 月牙本体颜色（浅金白）
solid = Image.new("RGBA", (S, S), (0xF6, 0xE7, 0xC8, 235))
moon_layer = Image.composite(solid, Image.new("RGBA", (S, S), (0, 0, 0, 0)), moon_mask)
img = Image.alpha_composite(img, moon_layer)

# ---------------------------------------------------------------- 缩回 1024 并输出
final = img.convert("RGB").resize((OUT, OUT), Image.LANCZOS)
OUT_PATH = ("/Users/moon/Documents/moon_pro/dingClock/"
            "DingClock/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
final.save(OUT_PATH, "PNG")
print(f"✅ 已生成 {OUT_PATH}  尺寸 {final.size}  模式 {final.mode}")
