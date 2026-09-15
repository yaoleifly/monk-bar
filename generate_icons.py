#!/usr/bin/env python3
"""
generate_icons.py — 根据 monk.party 视觉与 Apple HIG 规范生成 macOS App 图标与资源
- 生成 1024x1024 超高分辨率母图（符合 macOS squircle 比例、深度渐变、环境光晕与内高光）
- 生成 .iconset 尺寸梯度并通过 macOS 官方 iconutil 编译为 AppIcon.icns
- 导出 Resources/ 所需的高清配图
"""

import os
import subprocess
import shutil
from PIL import Image, ImageDraw, ImageFilter

def build_app_icon(output_dir):
    os.makedirs(output_dir, exist_ok=True)
    size = 1024
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Apple macOS App Icon 规范：
    # 1024x1024 画布内，主体 Tile 为 824x824（边距 100），圆角约 185px (Squircle 比例)
    tile_size = 824
    left = (size - tile_size) // 2
    top = (size - tile_size) // 2
    right = left + tile_size
    bottom = top + tile_size
    radius = 185

    # 1. 深度立体阴影层（双层柔和弥散，符合 macOS Sonoma / Sequoia 视觉）
    shadow_deep = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw1 = ImageDraw.Draw(shadow_deep)
    sdraw1.rounded_rectangle([left, top + 28, right, bottom + 28], radius=radius, fill=(0, 0, 0, 95))
    shadow_deep = shadow_deep.filter(ImageFilter.GaussianBlur(32))

    shadow_tight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw2 = ImageDraw.Draw(shadow_tight)
    sdraw2.rounded_rectangle([left, top + 12, right, bottom + 12], radius=radius, fill=(0, 0, 0, 135))
    shadow_tight = shadow_tight.filter(ImageFilter.GaussianBlur(14))

    img.alpha_composite(shadow_deep)
    img.alpha_composite(shadow_tight)

    # 2. 背景 Squircle Tile
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle([left, top, right, bottom], radius=radius, fill=255)

    # 深空钛黑/幽蓝渐变背景：顶部 #1E293B (30,41,59) -> 中部 #0F172A (15,23,42) -> 底部 #030712 (3,7,18)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(top, bottom):
        t = (y - top) / tile_size
        r = int(30 * (1 - t) + 6 * t)
        g = int(41 * (1 - t) + 10 * t)
        b = int(59 * (1 - t) + 18 * t)
        line = ImageDraw.Draw(bg)
        line.line([(left, y), (right, y)], fill=(r, g, b, 255))

    # 顶部 1px 细微内沿高光（Apple 材质感）
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rdraw = ImageDraw.Draw(rim)
    rdraw.rounded_rectangle([left, top, right, bottom], radius=radius, outline=(255, 255, 255, 42), width=2)
    bg.paste(rim, (0, 0), rim)
    img.paste(bg, (0, 0), mask)

    # 3. 僧侣火焰环境光晕（Ambient Glow）
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse([290, 310, 734, 750], fill=(234, 88, 12, 115))
    glow = glow.filter(ImageFilter.GaussianBlur(68))
    img.alpha_composite(glow)

    # 4. 僧侣冥想火焰标志（基于 monk.party SVG 精确投射）
    scale = 8.85
    ox = 512 - 32 * scale
    oy = 512 - 34 * scale

    def pt(x, y):
        return (ox + x * scale, oy + y * scale)

    emblem = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 火焰主体蒙版
    flame_mask = Image.new("L", (size, size), 0)
    fdraw = ImageDraw.Draw(flame_mask)

    # 头部（圆球）
    hcx, hcy = pt(32, 18)
    hr = 5.25 * scale
    fdraw.ellipse([hcx - hr, hcy - hr, hcx + hr, hcy + hr], fill=255)

    # 僧袍左翼与右翼
    poly_l = [pt(21, 50), pt(26, 28), pt(32, 36), pt(28, 50)]
    fdraw.polygon(poly_l, fill=255)
    poly_r = [pt(43, 50), pt(38, 28), pt(32, 36), pt(36, 50)]
    fdraw.polygon(poly_r, fill=255)

    # 僧袍底部微弧连接
    poly_base = [pt(21, 50), pt(28, 50), pt(32, 52.5), pt(36, 50), pt(43, 50), pt(32, 53.5)]
    fdraw.polygon(poly_base, fill=255)

    # 火焰渐变填色：顶部金黄 #FDE047 -> 中部燃橙 #F97316 -> 底部赤橙 #EA580C
    flame_grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    f_top = int(oy + 12 * scale)
    f_bot = int(oy + 54 * scale)
    f_height = max(1, f_bot - f_top)

    for y in range(f_top, f_bot + 1):
        t = (y - f_top) / f_height
        if t < 0.35:
            st = t / 0.35
            r = int(253 * (1 - st) + 249 * st)
            g = int(224 * (1 - st) + 115 * st)
            b = int(71 * (1 - st) + 22 * st)
        else:
            st = (t - 0.35) / 0.65
            r = int(249 * (1 - st) + 234 * st)
            g = int(115 * (1 - st) + 88 * st)
            b = int(22 * (1 - st) + 12 * st)
        fg_line = ImageDraw.Draw(flame_grad)
        fg_line.line([(0, y), (size, y)], fill=(r, g, b, 255))

    emblem.paste(flame_grad, (0, 0), flame_mask)

    # 心灵微光/合十核心（纯白纯净菱形微光）
    core_mask = Image.new("L", (size, size), 0)
    cdraw = ImageDraw.Draw(core_mask)
    poly_c = [pt(32, 27), pt(35.2, 37), pt(32, 48), pt(28.8, 37)]
    cdraw.polygon(poly_c, fill=255)

    core = Image.new("RGBA", (size, size), (255, 255, 255, 252))
    emblem.paste(core, (0, 0), core_mask)

    # 标志软辉光融合
    emblem_soft = emblem.filter(ImageFilter.GaussianBlur(12))
    img.alpha_composite(emblem_soft)
    img.alpha_composite(emblem)

    # 保存 1024 完整母图
    master_png = os.path.join(output_dir, "AppIcon_1024.png")
    img.save(master_png)

    # 导出 128x128 预览图用于 UI 显示
    ui_icon = img.resize((128, 128), Image.Resampling.LANCZOS)
    ui_icon.save(os.path.join(output_dir, "AppIcon_128.png"))

    # 生成 macOS .iconset
    iconset_dir = os.path.join(output_dir, "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)
    icon_specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for filename, sz in icon_specs:
        resized = img.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))

    # 运行 iconutil 生成 AppIcon.icns
    icns_path = os.path.join(output_dir, "AppIcon.icns")
    res = subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"iconutil failed: {res.stderr}")

    # 清理临时 iconset
    shutil.rmtree(iconset_dir, ignore_errors=True)
    print(f"✓ 已生成 AppIcon.icns ({os.path.getsize(icns_path) // 1024} KB)")
    print(f"✓ 已生成母图 {master_png}")

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build")
    build_app_icon(out)
