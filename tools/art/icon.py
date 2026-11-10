"""아이콘(assets/icon.png)을 코드로 그린다.  python3 tools/art/icon.py  (pillow 필요)"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets', 'icon.png')
im = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(im)
d.rounded_rectangle([2, 2, 62, 62], 14, fill=(80, 160, 232, 255))
# 구름
for x, y, r in [(16, 46, 9), (28, 50, 10), (44, 48, 9), (52, 52, 7)]:
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 230))
# 보드 (비스듬히)
d.polygon([(8, 34), (44, 20), (56, 22), (54, 27), (16, 41), (9, 40)], fill=(255, 214, 74, 255), outline=(40, 50, 90, 255))
d.line([(14, 36), (48, 23)], fill=(255, 255, 255, 255), width=2)
# 분사구 빛
d.ellipse([3, 35, 11, 43], fill=(140, 240, 255, 255))
im.save(OUT)
