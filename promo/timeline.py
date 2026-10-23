"""Shot timing shared by the Blender scene, the audio and the compositor.

Frames are 1-based and every shot starts on a beat: 100 BPM at 30 fps is 18 frames per beat.
"""

FPS = 30
BPM = 100
BEAT = 18
WIDTH, HEIGHT = 1920, 1080

_SHOT_BEATS = [
    ("macro", 7),    # 微距：衣杆、木夹和便签
    ("hotkey", 6),   # ⌃⌥N 三个按键按下
    ("compose", 8),  # 书写窗口逐字输入
    ("submit", 2),   # ⌘↵ 按下
    ("hang", 7),     # 便签飞上衣杆、木夹夹住
    ("reveal", 6),   # 拉远：衣杆在屏幕顶部
    ("edges", 8),    # 上 → 右 → 下 → 左
    ("drag", 7),     # 拖动排序
    ("library", 5),  # 全部选题窗口
    ("end", 9),      # 片尾
]

SHOTS = {}
_frame = 1
for _name, _beats in _SHOT_BEATS:
    SHOTS[_name] = (_frame, _frame + _beats * BEAT)  # [start, end)
    _frame += _beats * BEAT
FRAME_START = 1
FRAME_END = _frame - 1
ORDER = [name for name, _ in _SHOT_BEATS]


def start(name):
    return SHOTS[name][0]


def end(name):
    return SHOTS[name][1]


def at(name, seconds):
    """Frame number `seconds` into shot `name`."""
    return SHOTS[name][0] + round(seconds * FPS)


def beat(name, n):
    """Frame of beat `n` (0-based, may be fractional) inside shot `name`."""
    return SHOTS[name][0] + round(n * BEAT)
