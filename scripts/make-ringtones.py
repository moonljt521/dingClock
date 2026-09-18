#!/usr/bin/env python3
"""
手绘闹钟铃声（纯数学合成，不借助任何素材库 / 第三方音源）。

输出 5 个 .caf 进 App 包（DingClock/Resources/Sounds/），
铃声名与 DingClock/Core/Alarm/Ringtone.swift 里的 RingtoneCatalog 一一对应：
    bell_classic  经典钟声 —— 880Hz 基频 + 谐波，指数衰减
    gentle_rise   轻柔渐强 —— 音量与音高同时缓慢爬升，不会一秒吓醒
    birds         清晨鸟鸣 —— 三段快速上滑的啁啾
    soft_pulse    柔和嗡鸣 —— 低频 + 4Hz 颤音，音量偏小
（"系统默认"用 AlarmKit 的 .default，不需要音频文件。）

参数刻意保守：44.1kHz / 16bit / 单声道 / 每段 ≤4 秒（系统会循环播放），
峰值 0.8，避免削波破音。
"""
import math
import struct
import subprocess
import wave
import os

SR = 44100
OUT_DIR = ("/Users/moon/Documents/moon_pro/dingClock/"
           "DingClock/Resources/Sounds")

def envelope_decay(t, dur, power=4.0):
    """指数衰减包络"""
    return math.exp(-power * t / dur)

def render(name, dur, sample_fn):
    n = int(SR * dur)
    frames = bytearray()
    peak = 0.0
    samples = []
    for i in range(n):
        t = i / SR
        v = max(-1.0, min(1.0, sample_fn(t)))
        samples.append(v)
        peak = max(peak, abs(v))
    # 归一化到 0.8，防止削波
    scale = 0.8 / peak if peak > 0 else 1.0
    for v in samples:
        v *= scale
        # 5ms 淡入淡出，消除首尾爆音
        idx = int(len(samples))
        frames += struct.pack("<h", int(v * 32767))
    wav_path = f"/tmp/{name}.wav"
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    os.makedirs(OUT_DIR, exist_ok=True)
    caf = os.path.join(OUT_DIR, f"{name}.caf")
    subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1",
                    wav_path, caf], check=True)
    os.remove(wav_path)
    print(f"  ✅ {name}.caf  {dur:.1f}s  {os.path.getsize(caf)/1024:.0f} KB")

def fade(t, dur, ms=5):
    """首尾淡入淡出"""
    edge = ms / 1000.0
    if t < edge:
        return t / edge
    if t > dur - edge:
        return (dur - t) / edge
    return 1.0

# ---------------------------------------------------------------- 经典钟声
def bell_classic(t):
    dur = 2.6
    env = envelope_decay(t, dur, 3.2) * fade(t, dur)
    # 基频 + 两个非整数倍谐波，接近真实钟的金属质感
    v = (math.sin(2 * math.pi * 880 * t) * 0.6
         + math.sin(2 * math.pi * 880 * 2.76 * t) * 0.25
         + math.sin(2 * math.pi * 880 * 5.4 * t) * 0.12)
    return v * env

# ---------------------------------------------------------------- 轻柔渐强
def gentle_rise(t):
    dur = 4.0
    ramp = min(1.0, t / dur) ** 1.5          # 音量缓慢爬升
    freq = 392 + (523 - 392) * min(1.0, t / dur)  # G4 → C5，缓缓上行
    env = fade(t, dur)
    # 相位积分保证频率连续，不会爆裂
    phase = 2 * math.pi * (392 * t + (523 - 392) * t * t / (2 * dur))
    v = (math.sin(phase) * 0.7 + math.sin(2 * phase) * 0.2) * ramp * env
    return v

# ---------------------------------------------------------------- 清晨鸟鸣
def chirp(t, start, dur, f0, f1):
    """一段快速上滑的啁啾"""
    if not (start <= t < start + dur):
        return 0.0
    p = (t - start) / dur
    freq = f0 + (f1 - f0) * p
    phase = 2 * math.pi * (f0 * (t - start) + (f1 - f0) * (t - start) ** 2 / (2 * dur))
    env = math.sin(math.pi * p) ** 2
    return math.sin(phase) * env

def birds(t):
    dur = 3.2
    env = fade(t, dur)
    v = (chirp(t, 0.00, 0.14, 2400, 3600) * 0.8
         + chirp(t, 0.22, 0.12, 2800, 3900) * 0.7
         + chirp(t, 0.95, 0.16, 2300, 3500) * 0.8
         + chirp(t, 1.25, 0.11, 2900, 4000) * 0.65
         + chirp(t, 2.05, 0.15, 2400, 3700) * 0.8
         + chirp(t, 2.35, 0.12, 2850, 3950) * 0.7)
    return v * env

# ---------------------------------------------------------------- 柔和嗡鸣
def soft_pulse(t):
    dur = 2.2
    env = fade(t, dur)
    tremolo = 0.65 + 0.35 * math.sin(2 * math.pi * 4.0 * t)   # 4Hz 颤音
    v = (math.sin(2 * math.pi * 233 * t) * 0.55          # Bb3
         + math.sin(2 * math.pi * 233 * 2 * t) * 0.15)
    return v * tremolo * env * 0.8

print("==> 生成铃声（纯合成，无外部素材）")
render("bell_classic", 2.6, bell_classic)
render("gentle_rise",  4.0, gentle_rise)
render("birds",        3.2, birds)
render("soft_pulse",   2.2, soft_pulse)
print(f"✅ 输出目录：{OUT_DIR}")
