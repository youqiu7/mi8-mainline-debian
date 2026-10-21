#!/usr/bin/env python3
# com_monitor.py —— PC 端串口监控（自动等端口、时间戳日志、关键字、可定时发送）
# 依赖同目录 com_probe.py 的 Win32 串口封装
#
# 用法:
#   python com_monitor.py --auto-wait --duration 600 --log boot.log --until "login:|Kernel panic"
#   python com_monitor.py --port COM7 --duration 120 --send-at 30 --send "echo PROBE" 
#   python com_monitor.py --port COM7 --duration 60 --chat      # 交互式
import argparse, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import com_probe as cp


def port_exists(name):
    try:
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.QueryDosDeviceW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
        buf = ctypes.create_unicode_buffer(1024)
        return k32.QueryDosDeviceW(name, buf, 1024) != 0
    except Exception:
        return True


def wait_port(name, timeout=180):
    t0 = time.time()
    while time.time() - t0 < timeout:
        if port_exists(name):
            h = cp.open_port(name)
            if h is not None:
                return h
        time.sleep(1)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM7")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--duration", type=int, default=300)
    ap.add_argument("--log", default="")
    ap.add_argument("--auto-wait", action="store_true")
    ap.add_argument("--send-at", type=int, default=-1, help="第 N 秒发送 --send")
    ap.add_argument("--send", default="")
    ap.add_argument("--until", default="")
    ap.add_argument("--chat", action="store_true", help="交互：stdin 每行作为命令发送")
    a = ap.parse_args()

    h = wait_port(a.port, 240) if a.auto_wait else cp.open_port(a.port, a.baud)
    if h is None:
        print(f"[monitor] 无法打开 {a.port}")
        return 2

    logf = open(a.log, "ab") if a.log else None
    t0 = time.time()
    sent = False
    total = 0
    acc = ""
    print(f"[monitor] {a.port} 开始，{a.duration}s，日志={a.log or '(仅屏幕)'}")

    while time.time() - t0 < a.duration:
        elapsed = time.time() - t0
        if a.send and not sent and elapsed >= a.send_at:
            cp.send(h, a.send.encode() + b"\r")
            sent = True
        if a.chat:
            import select
            r, _, _ = select.select([sys.stdin], [], [], 0)
            if r:
                line = sys.stdin.readline()
                if line:
                    cp.send(h, line.strip().encode() + b"\r")
        data = cp.read_for(h, 0.5, quiet_print=True)
        if data:
            total += len(data)
            ts = f"[T+{elapsed:6.1f}s] "
            text = data.decode("utf-8", "replace")
            acc += text
            if logf:
                logf.write((ts + text.replace("\n", "\n" + ts)).encode("utf-8", "replace"))
                logf.flush()
            sys.stdout.write(ts + text.replace("\n", "\n" + ts))
            sys.stdout.flush()
            if a.until:
                m = re.search(a.until, acc)
                if m:
                    print(f"\n[monitor] 命中 /{a.until}/ at T+{elapsed:.1f}s")
                    break

    print(f"\n[monitor] 结束，共 {total} 字节")
    if logf:
        logf.close()
    try:
        cp.k32.CloseHandle(h)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
