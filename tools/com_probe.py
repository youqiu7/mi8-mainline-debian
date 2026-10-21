#!/usr/bin/env python3
# com_probe.py —— 用 Win32 API 直接读写串口（绕开 .NET SerialPort 阻塞问题）
# 用法:
#   python com_probe.py --port COM7 --read 10
#   python com_probe.py --port COM7 --send "echo PROBE_OK" --read 12
import argparse, ctypes, sys, time
from ctypes import wintypes

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
INVALID_HANDLE_VALUE = wintypes.HANDLE(-1).value
SETDTR = 5
SETRTS = 3
CLRDTR = 6
CLRRTS = 4


class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [("ReadIntervalTimeout", wintypes.DWORD),
                ("ReadTotalTimeoutMultiplier", wintypes.DWORD),
                ("ReadTotalTimeoutConstant", wintypes.DWORD),
                ("WriteTotalTimeoutMultiplier", wintypes.DWORD),
                ("WriteTotalTimeoutConstant", wintypes.DWORD)]


class DCB(ctypes.Structure):
    _fields_ = [("DCBlength", wintypes.DWORD),
                ("BaudRate", wintypes.DWORD),
                ("fFlags", wintypes.DWORD),
                ("wReserved", wintypes.WORD),
                ("XonLim", wintypes.WORD),
                ("XoffLim", wintypes.WORD),
                ("ByteSize", wintypes.BYTE),
                ("Parity", wintypes.BYTE),
                ("StopBits", wintypes.BYTE),
                ("XonChar", ctypes.c_char),
                ("XoffChar", ctypes.c_char),
                ("ErrorChar", ctypes.c_char),
                ("EofChar", ctypes.c_char),
                ("EvtChar", ctypes.c_char),
                ("wReserved1", wintypes.WORD)]


def open_port(name, baud=115200):
    k32.CreateFileW.restype = wintypes.HANDLE
    k32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD,
                                wintypes.HANDLE]
    k32.ReadFile.argtypes = [wintypes.HANDLE, wintypes.LPVOID, wintypes.DWORD,
                             ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
    k32.WriteFile.argtypes = [wintypes.HANDLE, wintypes.LPCVOID, wintypes.DWORD,
                              ctypes.POINTER(wintypes.DWORD), wintypes.LPVOID]
    k32.GetCommState.argtypes = [wintypes.HANDLE, ctypes.POINTER(DCB)]
    k32.SetCommState.argtypes = [wintypes.HANDLE, ctypes.POINTER(DCB)]
    k32.SetCommTimeouts.argtypes = [wintypes.HANDLE, ctypes.POINTER(COMMTIMEOUTS)]
    k32.SetupComm.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD]
    k32.EscapeCommFunction.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    k32.PurgeComm.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    k32.CloseHandle.argtypes = [wintypes.HANDLE]

    h = k32.CreateFileW("\\\\.\\" + name, GENERIC_READ | GENERIC_WRITE, 0, None,
                        OPEN_EXISTING, 0, None)
    if h == INVALID_HANDLE_VALUE or h is None:
        err = ctypes.get_last_error()
        print(f"[open] FAIL {name} err={err} ({ctypes.FormatError(err)})")
        return None
    dcb = DCB()
    dcb.DCBlength = ctypes.sizeof(DCB)
    if not k32.GetCommState(h, ctypes.byref(dcb)):
        err = ctypes.get_last_error()
        print(f"[open] GetCommState FAIL err={err}")
    dcb.BaudRate = baud
    dcb.ByteSize = 8
    dcb.Parity = 0        # NOPARITY
    dcb.StopBits = 0      # ONESTOPBIT
    dcb.fFlags |= 0x1     # fBinary
    dcb.fFlags = (dcb.fFlags & ~(0x3 << 4)) | (0x1 << 4)   # fDtrControl = ENABLE
    dcb.fFlags = (dcb.fFlags & ~(0x3 << 12)) | (0x1 << 12)  # fRtsControl = ENABLE
    if not k32.SetCommState(h, ctypes.byref(dcb)):
        err = ctypes.get_last_error()
        print(f"[open] SetCommState FAIL err={err}")
    to = COMMTIMEOUTS(30, 0, 250, 0, 800)
    k32.SetCommTimeouts(h, ctypes.byref(to))
    k32.SetupComm(h, 65536, 65536)
    k32.EscapeCommFunction(h, SETDTR)
    k32.EscapeCommFunction(h, SETRTS)
    k32.PurgeComm(h, 0x0004 | 0x0008)  # PURGE_RXCLEAR|PURGE_TXCLEAR
    print(f"[open] OK {name} @{baud}")
    return h


def read_for(h, seconds, quiet_print=False):
    buf = ctypes.create_string_buffer(8192)
    nread = wintypes.DWORD()
    out = bytearray()
    end = time.time() + seconds
    while time.time() < end:
        ok = k32.ReadFile(h, buf, 8192, ctypes.byref(nread), None)
        if not ok:
            err = ctypes.get_last_error()
            if err in (0, 121):  # timeout
                continue
            print(f"[read] error {err} ({ctypes.FormatError(err)})")
            break
        if nread.value:
            chunk = buf.raw[:nread.value]
            out += chunk
            if not quiet_print:
                sys.stdout.write(chunk.decode("utf-8", "replace"))
                sys.stdout.flush()
        else:
            time.sleep(0.01)
    return bytes(out)


def send(h, data):
    n = wintypes.DWORD()
    ok = k32.WriteFile(h, data, len(data), ctypes.byref(n), None)
    if not ok:
        err = ctypes.get_last_error()
        print(f"[write] FAIL err={err} ({ctypes.FormatError(err)})")
        return False
    print(f"[write] {len(data)}B ok")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM7")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--read", type=int, default=10)
    ap.add_argument("--send", default="")
    ap.add_argument("--enter-first", action="store_true")
    a = ap.parse_args()

    h = open_port(a.port, a.baud)
    if h is None:
        return 2
    if a.enter_first:
        send(h, b"\r")
        time.sleep(0.8)
    if a.send:
        send(h, a.send.encode() + b"\r")
    data = read_for(h, a.read)
    print(f"\n[total {len(data)} bytes]")
    if data:
        print("[repr]", repr(data[:600]))
    k32.CloseHandle(h)
    return 0


if __name__ == "__main__":
    sys.exit(main())
