#!/usr/bin/env python3
"""
手绘闹钟铃声（纯数学合成，无第三方素材/音源）。

12 段铃声 + 系统默认，与 DingClock/Core/Alarm/Ringtone.swift 的 RingtoneCatalog 对应。

格式：CAF / AAC 单声道（约 7.5:1 压缩）。
  · 12 段合计 ~200KB；AVAudioPlayer 试听与 AlarmKit 响铃共用这批文件
"""
import math
import random
import struct
import subprocess
import wave
import os

SR = 22050                      # 22050 对闹钟音色足够（最高频内容 < 11kHz）
OUT_DIR = ("/Users/moon/Documents/moon_pro/dingClock/"
           "DingClock/Resources/Sounds")

# ---------------------------------------------------------------- 基础设施

def render(name, dur, sample_fn, gain=0.8):
    """采样函数 → 归一化 → wav → afconvert → 压缩 caf"""
    n = int(SR * dur)
    samples = [max(-1.0, min(1.0, sample_fn(i / SR))) for i in range(n)]
    peak = max(abs(v) for v in samples) or 1.0
    scale = gain / peak
    frames = bytearray()
    for v in samples:
        frames += struct.pack("<h", int(v * scale * 32767))

    wav = f"/tmp/{name}.wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))

    os.makedirs(OUT_DIR, exist_ok=True)
    caf = os.path.join(OUT_DIR, f"{name}.caf")
    # IMA4：4:1 无损听感压缩，iOS 通知声音的标准格式
    subprocess.run(["afconvert", "-f", "caff", "-d", "aac", "-c", "1",
                    wav, caf], check=True)
    os.remove(wav)
    print(f"  ✅ {name:<12} {dur:>4.1f}s  {os.path.getsize(caf)/1024:>4.0f} KB")

def fade(t, dur, ms=8):
    edge = ms / 1000.0
    if t < edge: return t / edge
    if t > dur - edge: return max(0.0, (dur - t) / edge)
    return 1.0

def decay_env(t, dur, power):
    return math.exp(-power * t / dur)

def pluck(freq, t, t0, dur, decay=6.0):
    """拨弦衰减音（钢琴/八音盒/风铃通用形状）"""
    if t < t0: return 0.0
    u = t - t0
    if u > dur: return 0.0
    return math.sin(2 * math.pi * freq * u) * math.exp(-decay * u / dur)

# ---------------------------------------------------------------- 12 段音色

def bell_classic(t):
    dur = 2.6
    env = decay_env(t, dur, 3.2) * fade(t, dur)
    return (math.sin(2*math.pi*880*t) * 0.6
            + math.sin(2*math.pi*880*2.76*t) * 0.25
            + math.sin(2*math.pi*880*5.4*t) * 0.12) * env

def gentle_rise(t):
    dur = 4.0
    ramp = min(1.0, t/dur) ** 1.5
    phase = 2*math.pi*(392*t + (523-392)*t*t/(2*dur))
    return (math.sin(phase)*0.7 + math.sin(2*phase)*0.2) * ramp * fade(t, dur)

def birds(t):
    dur = 3.2
    def chirp(t, s, d, f0, f1, g):
        if not (s <= t < s+d): return 0.0
        p = (t-s)/d
        ph = 2*math.pi*(f0*(t-s) + (f1-f0)*(t-s)**2/(2*d))
        return math.sin(ph) * math.sin(math.pi*p)**2 * g
    return (chirp(t,0.00,.14,2400,3600,.8) + chirp(t,0.22,.12,2800,3900,.7)
            + chirp(t,0.95,.16,2300,3500,.8) + chirp(t,1.25,.11,2900,4000,.65)
            + chirp(t,2.05,.15,2400,3700,.8) + chirp(t,2.35,.12,2850,3950,.7)) * fade(t, dur)

def soft_pulse(t):
    dur = 2.2
    trem = 0.65 + 0.35*math.sin(2*math.pi*4*t)
    return (math.sin(2*math.pi*233*t)*0.55 + math.sin(2*math.pi*466*t)*0.15) * trem * fade(t, dur) * 0.8

def drop(t):
    """水滴：音高快速下坠的「叮咚」，间隔重复"""
    dur = 2.8
    def one(u):
        if u > 0.25: return 0.0
        freq = 1800 - 1400 * (u / 0.25)
        return math.sin(2*math.pi*freq*u) * math.exp(-9*u/0.25)
    v = one(t % 0.95) + one((t + 0.4) % 0.95) * 0.6
    return v * fade(t, dur)

def wind_chime(t):
    """风铃：五声音阶高音区，随机错落的长衰减"""
    dur = 4.0
    rng = random.Random(7)                       # 固定种子，每次生成结果一致
    scale = [1046, 1174, 1318, 1568, 1760]       # C6 D6 E6 G6 A6
    notes = sorted([(rng.uniform(0, 2.8), rng.choice(scale), rng.uniform(0.5, 0.9))
                    for _ in range(7)])
    v = 0.0
    for start, freq, g in notes:
        v += pluck(freq, t, start, 1.8, 3.5) * g
    return v * fade(t, dur)

def piano_arp(t):
    """钢琴琶音：C4-E4-G4-C5 分解和弦，上行再回落"""
    dur = 3.2
    seq = [262, 330, 392, 523, 392, 330, 262, 330]
    step = 0.22
    v = 0.0
    for i, freq in enumerate(seq):
        v += pluck(freq, t, i*step, 1.4, 5.0) * 0.8
        v += pluck(freq*2, t, i*step, 0.9, 7.0) * 0.2   # 高次谐波提亮
    return v * fade(t, dur)

def xylophone(t):
    """木琴：五声音阶短促下行，木质颗粒感"""
    dur = 2.8
    seq = [1318, 1174, 1046, 880, 1046, 784]
    v = 0.0
    for i, freq in enumerate(seq):
        u = t - i*0.38
        if 0 <= u < 0.5:
            v += (math.sin(2*math.pi*freq*u) * 0.7
                  + math.sin(2*math.pi*freq*3.01*u) * 0.18) * math.exp(-11*u/0.5)
    return v * fade(t, dur)

def music_box(t):
    """八音盒：小星星开头一句，明亮细高音"""
    dur = 4.0
    melody = [523, 523, 784, 784, 880, 880, 784]      # C C G G A A G
    v = 0.0
    for i, freq in enumerate(melody):
        u = t - i*0.42
        if 0 <= u < 1.2:
            v += (math.sin(2*math.pi*freq*u) * 0.5
                  + math.sin(2*math.pi*freq*3*u) * 0.25
                  + math.sin(2*math.pi*freq*5.4*u) * 0.1) * math.exp(-3.5*u)
    return v * fade(t, dur)

def guitar(t):
    """吉他扫弦：六弦依次拨响，衰减正弦叠加近似拨弦质感"""
    dur = 3.0
    freqs = [82.4, 110, 146.8, 196, 246.9, 329.6]     # 标准调弦 E2→E4
    for i, freq in enumerate(freqs):
        u = t - i*0.09
        if 0 <= u < 2.0:
            pass
    # 上面只做时间窗判断；实际发声在下方统一算（避免每根弦重复循环）
    v = 0.0
    for i, freq in enumerate(freqs):
        u = t - i*0.09
        if 0 <= u < 2.0:
            v += (math.sin(2*math.pi*freq*u) * 0.5
                  + math.sin(2*math.pi*freq*2*u) * 0.25
                  + math.sin(2*math.pi*freq*3*u) * 0.12) * math.exp(-2.2*u)
    return v * fade(t, dur)

def ebeat(t):
    """电子节拍：双音交替，轻微软削波出 8-bit 味"""
    dur = 2.4
    step = int(t / 0.15)
    freq = 660 if step % 2 == 0 else 880
    u = t - step * 0.15
    env = math.exp(-14*u) * (0.6 + 0.4 * ((step % 4) == 0))
    v = max(-0.7, min(0.7, math.sin(2*math.pi*freq*u) * 1.6))
    return v * env * fade(t, dur)

def sunrise_horn(t):
    """晨号：温暖的号角和声，两短一长"""
    dur = 3.4
    def note(u):
        if u < 0: return 0.0
        env = min(1.0, u/0.08) * math.exp(-2.0*u)
        return (math.sin(2*math.pi*330*u) * 0.55
                + math.sin(2*math.pi*415*u) * 0.3
                + math.sin(2*math.pi*494*u) * 0.15) * env
    v = note(t) + note(t-0.45) + note(t-0.9)*1.3
    return v * fade(t, dur)

ALL = [
    ("bell_classic", 2.6, bell_classic),
    ("gentle_rise",  4.0, gentle_rise),
    ("birds",        3.2, birds),
    ("soft_pulse",   2.2, soft_pulse),
    ("drop",         2.8, drop),
    ("wind_chime",   4.0, wind_chime),
    ("piano_arp",    3.2, piano_arp),
    ("xylophone",    2.8, xylophone),
    ("music_box",    4.0, music_box),
    ("guitar",       3.0, guitar),
    ("ebeat",        2.4, ebeat),
    ("sunrise_horn", 3.4, sunrise_horn),
]

if __name__ == "__main__":
    print(f"==> 合成 {len(ALL)} 段铃声（纯数学，无外部素材）")
    for name, dur, fn in ALL:
        render(name, dur, fn)
    total = sum(os.path.getsize(os.path.join(OUT_DIR, f"{n}.caf")) for n, _, _ in ALL)
    print(f"✅ 共 {len(ALL)} 段，合计 {total/1024:.0f} KB → {OUT_DIR}")
