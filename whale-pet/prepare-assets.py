"""Prepare whale-pet assets.

三步，全部可重复执行（已存在的产物会跳过）：

1. convert   .webp -> .png             WPF 不能解码 webp
2. normalize 每个状态裁到「角色本体」再按统一高度重排到同一尺寸画布
              -> norm-<state>.png (512x512, 静图)
              -> norm-<state>.gif (320x256, 动图)
   这一步是为了修掉「点一下换状态图，角色尺寸就变了」的问题：
   各素材原始画布尺寸和角色占比都不同，而桌宠是把它 Uniform 塞进固定框渲染的，
   于是角色在屏幕上的大小会随状态跳变。归一化后所有状态的角色高度一致。

用法: python prepare-assets.py <assets-dir>
"""
import os
import sys
import glob

import numpy as np
from PIL import Image

ALPHA_MIN = 64          # 低于该 alpha 视为透明/杂色（源 GIF 边缘有极淡的杂点）
COVER = 0.06            # 一行/一列的不透明像素占比低于该值 -> 当作杂色，不计入角色框
GIF_PAD = 3             # 裁剪时留一点余量，避免裁到动作边缘

# 静图：512 画布，角色高 450 -> 在桌宠默认框(300x280)里渲染约 246px
STILL_CANVAS = (512, 512)
STILL_CHAR_H = 450
STILL_BOTTOM = 500

# 动图：300x300 画布，角色高 264 -> 同样约 246px（两套素材切换时大小不变）
GIF_CANVAS = (300, 300)
GIF_CHAR_H = 264
GIF_BOTTOM = 294

STILL_STATES = {
    'idle': 'bigfish-idle.png',
    'busy': 'bigfish-running.png',
    'waiting': 'bigfish-thinking.png',
    'sleep': 'bigfish-sleep.png',
    'pat': 'bigfish-wink.png',
    'greet': 'bigfish-greet.png',
}
GIF_STATES = {
    'idle': 'rlw-idle.gif',
    'busy': 'rlw-thinking.gif',
    'waiting': 'rlw-question.gif',
    'sleep': 'rlw-sleep.gif',
    'pat': 'rlw-pat.gif',
    'greet': 'rlw-happy.gif',
}


# --------------------------------------------------------------------------
# 角色本体检测
# --------------------------------------------------------------------------
def frames_rgba(path):
    im = Image.open(path)
    try:
        for i in range(getattr(im, 'n_frames', 1)):
            im.seek(i)
            yield np.array(im.convert('RGBA'))
    finally:
        im.close()


def cover_bbox(arr):
    """行列覆盖率包围盒：忽略边缘细碎杂点，只框住角色本体。"""
    mask = arr[:, :, 3] >= ALPHA_MIN
    h, w = mask.shape
    rows = np.where(mask.sum(axis=1) >= max(3, int(COVER * w)))[0]
    cols = np.where(mask.sum(axis=0) >= max(3, int(COVER * h)))[0]
    if len(rows) == 0 or len(cols) == 0:
        return None
    return (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)


def union_bbox(boxes):
    boxes = [b for b in boxes if b]
    if not boxes:
        return None
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def median_bbox(boxes):
    """逐帧框的中位数：动图里个别帧会带出细长杂点，中位数比并集稳得多。"""
    boxes = [b for b in boxes if b]
    if not boxes:
        return None
    arr = np.array(boxes)
    return tuple(int(v) for v in np.median(arr, axis=0))


def outside_pixels(frames, box):
    """统计落在 box 之外的不透明像素数（用来确认裁剪没有切到角色本体）。"""
    worst = 0
    for f in frames:
        mask = np.array(f)[:, :, 3] >= ALPHA_MIN
        keep = mask.copy()
        keep[box[1]:box[3], box[0]:box[2]] = False
        worst = max(worst, int(keep.sum()))
    return worst


# --------------------------------------------------------------------------
# 归一化
# --------------------------------------------------------------------------
def fit(bbox, canvas, char_h, bottom, width_limit_ratio=0.94):
    """算出缩放比和粘贴位置：角色高度固定 char_h，画布不够宽时退让（顶多略微变矮）。"""
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    cw, ch = canvas
    scale = min(char_h / bh, (cw * width_limit_ratio) / bw)
    new_w, new_h = max(1, round(bw * scale)), max(1, round(bh * scale))
    x = round((cw - new_w) / 2)
    y = bottom - new_h
    return scale, new_w, new_h, x, y


def normalize_still(src, dst, canvas=STILL_CANVAS, char_h=STILL_CHAR_H, bottom=STILL_BOTTOM):
    arr = next(frames_rgba(src))
    bbox = cover_bbox(arr)
    if not bbox:
        return None
    scale, nw, nh, x, y = fit(bbox, canvas, char_h, bottom)
    im = Image.open(src).convert('RGBA')
    crop = im.crop(bbox).resize((nw, nh), Image.LANCZOS)
    im.close()
    out = Image.new('RGBA', canvas, (0, 0, 0, 0))
    out.paste(crop, (x, y), crop)
    out.save(dst)
    return {'src': os.path.basename(src), 'bbox': bbox, 'char': (nw, nh), 'canvas': canvas}


def pad_box(bbox, size, pad=GIF_PAD):
    w, h = size
    return (max(0, bbox[0] - pad), max(0, bbox[1] - pad),
            min(w, bbox[2] + pad), min(h, bbox[3] + pad))


def robust_crop_box(boxes, size, pad=GIF_PAD):
    """稳健裁剪框：剔除面积离群的帧（那些帧里带细长杂点），再对其余帧取并集。

    这样既保住角色本体 + 脚下阴影 + 正常动作幅度，又不会被个别帧的杂点带偏。
    """
    boxes = [b for b in boxes if b]
    if not boxes:
        return None
    med = median_bbox(boxes)
    med_w = max(1, med[2] - med[0])
    med_h = max(1, med[3] - med[1])
    keep = []
    for b in boxes:
        w, h = b[2] - b[0], b[3] - b[1]
        if w > 1.6 * med_w or h > 1.6 * med_h:
            continue                      # 离群帧：多半是杂点撑大的
        keep.append(b)
    if not keep:
        keep = boxes
    return pad_box(union_bbox(keep), size, pad)


def normalize_gif(src, dst, canvas=GIF_CANVAS, char_h=GIF_CHAR_H, bottom=GIF_BOTTOM):
    im = Image.open(src)
    frames, delays = [], []
    try:
        for i in range(getattr(im, 'n_frames', 1)):
            im.seek(i)
            frames.append(im.convert('RGBA'))
            delays.append(int(im.info.get('duration', 100) or 100))
    finally:
        im.close()
    if not frames:
        return None

    # 整段动画共用一个裁剪框和一个缩放比，避免逐帧抖动；
    # 尺寸基准用「逐帧框的中位数」，贴合角色本体的常见大小。
    boxes = [cover_bbox(np.array(f)) for f in frames]
    crop_box = robust_crop_box(boxes, frames[0].size)
    ref = median_bbox(boxes)
    if not crop_box or not ref:
        return None
    # 缩放比只由「中位框」决定：角色本体在画布里始终占一样高。
    # 裁剪框可能比角色宽（动作/杂点），那部分超出画布就被裁掉，绝不反过来缩小角色。
    med_w = max(1, ref[2] - ref[0])
    med_h = max(1, ref[3] - ref[1])
    cw, ch = canvas
    scale = min(char_h / med_h, (cw * 0.96) / med_w)     # 第二个限值只对躺姿这类宽姿势生效
    nw = max(1, round((crop_box[2] - crop_box[0]) * scale))
    nh = max(1, round((crop_box[3] - crop_box[1]) * scale))
    x = round((cw - nw) / 2)                             # 可能为负 -> 由 PIL 在画布边裁掉
    y = bottom - nh

    out_frames = []
    for f in frames:
        crop = f.crop(crop_box).resize((nw, nh), Image.LANCZOS)
        frame_canvas = Image.new('RGBA', canvas, (0, 0, 0, 0))
        frame_canvas.paste(crop, (x, y), crop)
        out_frames.append(frame_canvas)

    out_frames[0].save(dst, save_all=True, append_images=out_frames[1:], duration=delays,
                       loop=0, disposal=2, optimize=False)
    return {'src': os.path.basename(src), 'bbox': crop_box,
            'char': (round((ref[2] - ref[0]) * scale), round((ref[3] - ref[1]) * scale)),
            'canvas': canvas, 'frames': len(out_frames),
            'dropped': outside_pixels(frames, crop_box)}


def convert_webp(d):
    for p in sorted(glob.glob(os.path.join(d, '*.webp'))):
        out = os.path.splitext(p)[0] + '.png'
        if os.path.exists(out):
            continue
        Image.open(p).convert('RGBA').save(out)
        print('  png  ' + os.path.basename(out))


def report(rows, label):
    print('\n-- %s --' % label)
    print('%-9s %-22s %-12s %-14s %s' % ('state', 'source', '裁剪框', '归一化后角色', '丢弃杂点px'))
    for state, r in rows:
        if not r:
            print('%-9s %-22s %s' % (state, '-', '(缺失/跳过)'))
            continue
        bw = r['bbox'][2] - r['bbox'][0]
        bh = r['bbox'][3] - r['bbox'][1]
        print('%-9s %-22s %-12s %-14s %s' % (state, r['src'], '%dx%d' % (bw, bh), '%dx%d' % r['char'],
                                             r.get('dropped', '-')))


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets')
    if not os.path.isdir(d):
        print('assets dir not found: ' + d)
        return 1
    print('prepare ' + d)
    convert_webp(d)

    still_rows, gif_rows = [], []
    for state, name in STILL_STATES.items():
        src = os.path.join(d, name)
        if not os.path.exists(src):
            still_rows.append((state, None))
            continue
        still_rows.append((state, normalize_still(src, os.path.join(d, 'norm-%s.png' % state))))

    for state, name in GIF_STATES.items():
        src = os.path.join(d, name)
        if not os.path.exists(src):
            gif_rows.append((state, None))
            continue
        gif_rows.append((state, normalize_gif(src, os.path.join(d, 'norm-%s.gif' % state))))

    report(still_rows, '静图归一化 canvas %dx%d / 角色高 %d' % (STILL_CANVAS + (STILL_CHAR_H,)))
    report(gif_rows, '动图归一化 canvas %dx%d / 角色高 %d' % (GIF_CANVAS + (GIF_CHAR_H,)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
