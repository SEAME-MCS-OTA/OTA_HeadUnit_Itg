import os
import re
import socket
import struct
import subprocess
from typing import Optional

try:
    import fcntl  # type: ignore
except Exception:
    fcntl = None  # type: ignore


def _normalize_ip(raw: str) -> Optional[str]:
    ip = str(raw or "").strip()
    if not ip or ip.startswith("127."):
        return None
    return ip


def _first_ipv4_from_text(text: str) -> Optional[str]:
    for match in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", str(text or "")):
        try:
            socket.inet_aton(match)
        except OSError:
            continue
        ip = _normalize_ip(match)
        if ip:
            return ip
    return None


def _ip_tool_candidates() -> list[str]:
    candidates = ["/usr/sbin/ip", "/sbin/ip", "/usr/bin/ip", "/bin/ip", "ip"]
    seen = set()
    resolved = []
    for c in candidates:
        if c in seen:
            continue
        seen.add(c)
        if c == "ip" or os.path.exists(c):
            resolved.append(c)
    return resolved


def _default_iface() -> Optional[str]:
    try:
        with open("/proc/net/route", "r", encoding="utf-8") as f:
            for line in f.readlines()[1:]:
                cols = line.strip().split()
                if len(cols) < 11:
                    continue
                iface, destination, flags = cols[0], cols[1], cols[3]
                if destination != "00000000":
                    continue
                if (int(flags, 16) & 0x2) == 0:
                    continue
                return iface
    except Exception:
        pass
    return None


def _iface_ipv4(iface: str) -> Optional[str]:
    if fcntl is None:
        return None
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        packed = struct.pack("256s", iface[:15].encode("utf-8"))
        res = fcntl.ioctl(sock.fileno(), 0x8915, packed)  # SIOCGIFADDR
        ip = _normalize_ip(socket.inet_ntoa(res[20:24]))
        if ip:
            return ip
    except Exception:
        return None
    finally:
        sock.close()
    return None


def _first_cmd_ip() -> Optional[str]:
    commands = []
    for ip_tool in _ip_tool_candidates():
        commands.append([ip_tool, "-4", "addr", "show", "scope", "global"])
        commands.append([ip_tool, "-4", "addr", "show"])
        commands.append([ip_tool, "addr", "show"])
    commands.append(["hostname", "-I"])
    for cmd in commands:
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
            ip = _first_ipv4_from_text(out)
            if ip:
                return ip
        except Exception:
            continue
    return None


def _fib_trie_ip() -> Optional[str]:
    try:
        with open("/proc/net/fib_trie", "r", encoding="utf-8") as f:
            ip = _first_ipv4_from_text(f.read())
            if ip:
                return ip
    except Exception:
        pass
    return None


def _get_ip_and_source() -> tuple[str, str]:
    cmd_ip = _first_cmd_ip()
    if cmd_ip:
        return cmd_ip, "cmd"

    seen = set()
    candidates = []
    dflt = _default_iface()
    if dflt:
        candidates.append(dflt)
    candidates.extend(["wlan0", "eth0"])

    for iface in candidates:
        if not iface or iface in seen:
            continue
        seen.add(iface)
        ip = _iface_ipv4(iface)
        if ip:
            return ip, f"ioctl:{iface}"

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = _normalize_ip(s.getsockname()[0])
        s.close()
        if ip:
            return ip, "route-socket"
    except Exception:
        pass

    try:
        ip = _normalize_ip(socket.gethostbyname(socket.gethostname()))
        if ip:
            return ip, "hostname"
    except Exception:
        pass

    fib_ip = _fib_trie_ip()
    if fib_ip:
        return fib_ip, "fib-trie"

    return "-", "none"
