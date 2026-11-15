#!/bin/sh
# Stone 12 proof: bare metal learns to listen. Compiles
# bare-examples/nifla-listen.nifla with `niflac --bare`, boots
# it in QEMU with no display, and drives it through the QEMU
# monitor:
#
#   1. The screen's third row must show "Ticks: " followed by
#      a number — the program's own writing of ticks() — and
#      the number must grow between two readings (the timer
#      interrupt is really ticking).
#   2. The monitor's `sendkey` types the word "nifla"; the
#      screen's first row must come to begin with "nifla" —
#      the program read the scancodes with readkey(), turned
#      them into letters itself, and echoed them.
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

ELF="$WORK/nifla-listen.elf"
if ! ./niflac --bare bare-examples/nifla-listen.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
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
    $QEMU -kernel "$ELF" -display none -m 32 -nic none \
        -monitor "unix:$SOCK,server,nowait" &
    QEMU_PID=$!
elif [ -x "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" ]; then
    "$HOME/qemu10-root/usr/lib64/ld-linux-x86-64.so.2" \
        --library-path "$HOME/qemu10-root/usr/lib/x86_64-linux-gnu:$HOME/qemu10-root/lib/x86_64-linux-gnu" \
        "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" \
        -kernel "$ELF" -display none -m 32 -nic none \
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


def command(text):
    global greeted
    if not greeted:
        read_until_prompt()
        greeted = True
    sock.sendall(text.encode() + b"\n")
    return read_until_prompt()


def screen_rows():
    """The first three rows of the text screen, as text."""
    try:
        out = command("xp /480bx 0xb8000")
    except (MonitorQuiet, OSError):
        return None
    data = []
    for line in out.splitlines():
        match = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if match:
            data += [int(part, 16) for part in match.group(1).split()]
    if len(data) < 480:
        return None
    chars = [chr(data[i]) if 32 <= data[i] < 127 else " " for i in range(0, 480, 2)]
    return ["".join(chars[i * 80:(i + 1) * 80]) for i in range(3)]


def tick_count(rows):
    """The number the program wrote after 'Ticks: ', or None."""
    if rows is None:
        return None
    row = rows[2]
    if not row.startswith("Ticks: "):
        return None
    digits = ""
    for ch in row[7:]:
        if ch.isdigit():
            digits += ch
        else:
            break
    return int(digits) if digits else None


def fail(why, rows=None):
    print(f"FAIL: {why}")
    if rows is not None:
        print(f"last rows read: {rows!r}")
    try:
        command("quit")
        sock.close()
    except Exception:
        pass
    sys.exit(1)


# 1. The tick count appears, and grows.
first = None
deadline = time.time() + 25
while time.time() < deadline:
    first = tick_count(screen_rows())
    if first is not None:
        break
    time.sleep(0.4)
if first is None:
    fail("the tick count never appeared on the screen", screen_rows())
time.sleep(1.5)
second = tick_count(screen_rows())
if second is None or second <= first:
    fail(f"the tick count did not grow ({first} then {second})", screen_rows())
print(f"ticks advanced: {first} -> {second}")

# 2. Type the word; it must be echoed on the first row.
for key in ["n", "i", "f", "l", "a"]:
    try:
        command(f"sendkey {key}")
    except (MonitorQuiet, OSError):
        fail(f"the monitor would not send key {key!r}")
    time.sleep(0.3)

rows = None
deadline = time.time() + 20
while time.time() < deadline:
    rows = screen_rows()
    if rows and rows[0].startswith("nifla"):
        break
    time.sleep(0.4)
if not (rows and rows[0].startswith("nifla")):
    fail("the typed word was never echoed", rows)
print(f"row 1 begins: {'nifla'!r} (echoed from the keyboard)")

try:
    command("quit")
    sock.close()
except Exception:
    pass
print("PASS nifla-listen (bare metal: the timer ticks and the keyboard is heard)")
sys.exit(0)
PYEOF
