#!/bin/sh
# Stone 13 proof: bare metal learns to remember. Compiles
# bare-examples/nifla-memory.nifla with `niflac --bare` and
# boots it in QEMU with a distinctive memory size (-m 96).
# Through the monitor's readback of the VGA text buffer:
#
#   1. The first row must begin "Memory total: " followed by
#      the number memorysize() gave — the sum of the usable
#      stretches in the loader's memory map. For -m 96 the
#      machine holds 100663296 bytes; the map's usable sum is
#      a little less (the firmware's reserved stretches are
#      not usable), so the number must land in the band
#      (94 MiB, 96 MiB] — measured on this bench: 100137984.
#   2. The second row must begin "Bytes OK": a 4 MiB block
#      from makebytes was filled with a pattern by a floor
#      block, verified byte by byte (zero mismatches), and
#      spot-checked from the Nifla side, length included.
#
# Prints PASS or FAIL. QEMU is the bench machine's extracted
# QEMU 10 (~/qemu10-root), as in run-bare.sh; set QEMU to a
# plain qemu-system-x86_64 command line instead if one is
# installed.

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null' EXIT

ELF="$WORK/nifla-memory.elf"
if ! ./niflac --bare bare-examples/nifla-memory.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
    echo "FAIL: niflac --bare refused or failed:"
    cat "$WORK/build.txt"
    exit 1
fi
echo "Built the bare binary:"
cat "$WORK/build.txt"

SOCK="$WORK/monitor.sock"
if [ -n "${QEMU:-}" ]; then
    # A ready-made QEMU command (words are split on purpose).
    # shellcheck disable=SC2086
    $QEMU -kernel "$ELF" -display none -m 96 -nic none \
        -monitor "unix:$SOCK,server,nowait" &
    QEMU_PID=$!
elif [ -x "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" ]; then
    "$HOME/qemu10-root/usr/lib64/ld-linux-x86-64.so.2" \
        --library-path "$HOME/qemu10-root/usr/lib/x86_64-linux-gnu:$HOME/qemu10-root/lib/x86_64-linux-gnu" \
        "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" \
        -kernel "$ELF" -display none -m 96 -nic none \
        -monitor "unix:$SOCK,server,nowait" \
        -L "$HOME/qemu10-root/usr/share/qemu" \
        -L "$HOME/qemu10-root/usr/share/seabios" \
        > "$WORK/qemu.txt" 2>&1 &
    QEMU_PID=$!
else
    echo "FAIL: no QEMU found (looked for ~/qemu10-root; set QEMU to a qemu-system-x86_64 command)"
    exit 1
fi

python3 - "$SOCK" <<'PYEOF'
import re
import socket
import sys
import time

sock_path = sys.argv[1]

deadline = time.time() + 15
sock = None
while time.time() < deadline:
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(sock_path)
        break
    except OSError:
        if sock is not None:
            sock.close()
        sock = None
        time.sleep(0.2)
if sock is None:
    print("FAIL: the QEMU monitor never opened")
    sys.exit(1)
sock.settimeout(5)


class MonitorQuiet(Exception):
    """The monitor hasn't answered yet — worth another try."""


def read_until_prompt():
    buf = b""
    while b"(qemu)" not in buf:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            raise MonitorQuiet()
        if not chunk:
            raise MonitorQuiet()
        buf += chunk
    return buf.decode(errors="replace")


greeted = False


def screen_rows():
    """The first two rows of the text screen, as text."""
    global greeted
    try:
        if not greeted:
            read_until_prompt()
            greeted = True
        sock.sendall(b"xp /320bx 0xb8000\n")
        out = read_until_prompt()
    except (MonitorQuiet, OSError):
        return None
    data = []
    for line in out.splitlines():
        match = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if match:
            data += [int(part, 16) for part in match.group(1).split()]
    if len(data) < 320:
        return None
    chars = [chr(data[i]) if 32 <= data[i] < 127 else " " for i in range(0, 320, 2)]
    return ["".join(chars[:80]), "".join(chars[80:])]


def finish(ok, rows):
    try:
        sock.sendall(b"quit\n")
        sock.close()
    except OSError:
        pass
    if ok:
        print("PASS nifla-memory (bare metal: the memory map is read and bytes live in real memory)")
        sys.exit(0)
    print(f"last rows read: {rows!r}")
    sys.exit(1)


rows = None
total = None
deadline = time.time() + 25
while time.time() < deadline:
    rows = screen_rows()
    if rows and rows[0].startswith("Memory total: ") and rows[1].startswith("Bytes"):
        digits = ""
        for ch in rows[0][14:]:
            if ch.isdigit():
                digits += ch
            else:
                break
        if digits:
            total = int(digits)
            break
    time.sleep(0.5)

if total is None:
    print("FAIL: the memory total and verdict never appeared")
    finish(False, rows)
print(f"row 1 begins: 'Memory total: {total}'")
if not (94 * 1048576 < total <= 96 * 1048576):
    print(f"FAIL: the total {total} is outside the band for a 96 MiB machine (94 MiB, 96 MiB]")
    finish(False, rows)
if not rows[1].startswith("Bytes OK"):
    print(f"FAIL: the verdict row does not begin with 'Bytes OK': {rows[1][:20]!r}")
    finish(False, rows)
print("row 2 begins: 'Bytes OK'")
finish(True, rows)
PYEOF
