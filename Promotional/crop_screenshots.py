from PIL import Image
import os

src = '/Users/tyeerth/Documents/MAC_software/SnapClick/snapclick_promotion.png'
out_dir = '/Users/tyeerth/Documents/MAC_software/SnapClick/Promotional/screenshots'

img = Image.open(src)
W, H = img.size

# 1. app icon - 调整 y 范围
icon = img.crop((75, 145, 220, 290))
icon.save(f'{out_dir}/app_icon.png')

# 清理不需要的旧文件
for f in ['window_pinned.png', 'window_settings.png']:
    fp = f'{out_dir}/{f}'
    if os.path.exists(fp):
        os.remove(fp)

print("最终素材:")
for f in sorted(os.listdir(out_dir)):
    if not f.startswith('full_screen') and not f.startswith('after_activate') and not f.startswith('main_attempt'):
        size = os.path.getsize(f'{out_dir}/{f}')
        print(f"  {f}: {size} bytes")
