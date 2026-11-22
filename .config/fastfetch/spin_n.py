#!/usr/bin/env python3
"""Spinning 3D ASCII "N" with fastfetch info printed beside it. Ctrl-C to quit."""
import math, re, subprocess, sys, time

W, H = 34, 18          # logo canvas in terminal cells
SHADES = " .,-~:;=!*#$@"
COLOR = "\033[36m"     # cyan
RESET = "\033[0m"
DEPTH = 1.6            # half thickness of the letter

# N outline (y up)
POLY = [(-3, -4), (-1.4, -4), (-1.4, 1.2), (1.4, -4), (3, -4), (3, 4),
        (1.4, 4), (1.4, -1.2), (-1.4, 4), (-3, 4)]


def inside(x, y):
    c = False
    n = len(POLY)
    for i in range(n):
        x1, y1 = POLY[i]
        x2, y2 = POLY[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def build_points(step=0.14):
    pts = []  # (x, y, z, nx, ny, nz)
    x = -3.0
    while x <= 3.0:
        y = -4.0
        while y <= 4.0:
            if inside(x, y):
                pts.append((x, y, DEPTH, 0, 0, 1))
                pts.append((x, y, -DEPTH, 0, 0, -1))
            y += step
        x += step
    n = len(POLY)
    for i in range(n):
        x1, y1 = POLY[i]
        x2, y2 = POLY[(i + 1) % n]
        dx, dy = x2 - x1, y2 - y1
        L = math.hypot(dx, dy)
        nx, ny = dy / L, -dx / L  # outward for this winding order handled by abs lighting
        steps = int(L / step) + 1
        for s in range(steps + 1):
            t = s / steps
            z = -DEPTH
            while z <= DEPTH:
                pts.append((x1 + dx * t, y1 + dy * t, z, nx, ny, 0))
                z += step
    return pts


def frame(pts, a, b):
    ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
    buf = [[" "] * W for _ in range(H)]
    zb = [[-1e9] * W for _ in range(H)]
    light = (0.4, 0.5, 0.77)
    for x, y, z, nx, ny, nz in pts:
        # rotate about Y (spin), then X (tilt)
        x1, z1 = x * ca + z * sa, -x * sa + z * ca
        y2, z2 = y * cb - z1 * sb, y * sb + z1 * cb
        nx1, nz1 = nx * ca + nz * sa, -nx * sa + nz * ca
        ny2, nz2 = ny * cb - nz1 * sb, ny * sb + nz1 * cb
        k = 22 / (z2 + 14)  # perspective
        px = int(W / 2 + x1 * k * 2.0)
        py = int(H / 2 - y2 * k * 0.95)
        if 0 <= px < W and 0 <= py < H and z2 > zb[py][px]:
            zb[py][px] = z2
            lum = abs(nx1 * light[0] + ny2 * light[1] + nz2 * light[2])
            buf[py][px] = SHADES[min(len(SHADES) - 1, int(lum * (len(SHADES) - 1) + 0.5))]
    return ["".join(r) for r in buf]


def info_lines():
    try:
        out = subprocess.run(["fastfetch", "--logo", "none", "--pipe", "false"],
                             capture_output=True, text=True, timeout=10).stdout
        return out.rstrip("\n").split("\n")
    except Exception:
        return []


def main():
    # usage: spin_n.py [seconds|forever]   (default 4 seconds, then the last frame stays)
    arg = sys.argv[1] if len(sys.argv) > 1 else "4"
    max_frames = None if arg == "forever" else int(float(arg) * 30)
    pts = build_points()
    info = info_lines()
    rows = max(H, len(info))
    sys.stdout.write("\n" * rows + "\033[?25l")
    n = 0
    try:
        while max_frames is None or n < max_frames:
            t = n * 0.08
            art = frame(pts, t, 0.25 * math.sin(t * 0.7))
            lines = []
            for i in range(rows):
                left = art[i] if i < H else " " * W
                right = info[i] if i < len(info) else ""
                lines.append(f"{COLOR}{left}{RESET}  {right}")
            sys.stdout.write(f"\033[{rows}A" + "\n".join(l + "\033[K" for l in lines) + "\n")
            sys.stdout.flush()
            n += 1
            time.sleep(1 / 30)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write("\033[?25h")


if __name__ == "__main__":
    main()
