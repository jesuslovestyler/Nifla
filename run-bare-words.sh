#!/bin/sh
# Stone 15 proof: words on the screen. Compiles
# bare-examples/nifla-words.nifla with `niflac --bare`,
# laying the screen library (barelib/screen.nifla) under it
# as a prelude, and boots it in QEMU. Through the monitor's
# readback of the VGA text buffer, the whole screen must
# show, in order:
#
#   row 0:  "Hello from Nifla!"   — a joined text, said
#   row 1:  "2 + 3 = 5"           — text joined with a number
#   row 2:  "1 2 3 4 "            — built a join at a time
#   row 3:  "42"                  — a said number
#   row 4:  "done"                — after the library's call
#   row 10: "Words!" at column 20, in color 14 (yellow) —
#           the library's placed word, checked by its
#           attribute byte as well as its letters.
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

ELF="$WORK/nifla-words.elf"
if ! ./niflac --bare bare-examples/nifla-words.nifla --prelude barelib/screen.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
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
    $QEMU -kernel "$ELF" -display none -nic none \
        -monitor "unix:$SOCK,server,nowait" &
    QEMU_PID=$!
elif [ -x "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" ]; then
    "$HOME/qemu10-root/usr/lib64/ld-linux-x86-64.so.2" \
        --library-path "$HOME/qemu10-root/usr/lib/x86_64-linux-gnu:$HOME/qemu10-root/lib/x86_64-linux-gnu" \
        "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" \
        -kernel "$ELF" -display none -nic none \
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


def screen():
    """The whole text screen: 25 rows of text, plus the raw
    bytes for checking a cell's color."""
    global greeted
    try:
        if not greeted:
            read_until_prompt()
            greeted = True
        sock.sendall(b"xp /4000bx 0xb8000\n")
        out = read_until_prompt()
    except (MonitorQuiet, OSError):
        return None
    data = []
    for line in out.splitlines():
        match = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if match:
            data += [int(part, 16) for part in match.group(1).split()]
    if len(data) < 4000:
        return None
    rows = []
    for r in range(25):
        chars = []
        for c in range(80):
            byte = data[(r * 80 + c) * 2]
            chars.append(chr(byte) if 32 <= byte < 127 else " ")
        rows.append("".join(chars))
    return rows, data


def finish(ok):
    try:
        sock.sendall(b"quit\n")
        sock.close()
    except OSError:
        pass
    if ok:
        print("PASS nifla-words (bare metal: joined words, said lines, and a placed word in its color)")
        sys.exit(0)
    sys.exit(1)


expected = {
    0: "Hello from Nifla!",
    1: "2 + 3 = 5",
    2: "1 2 3 4 ",
    3: "42",
    4: "done",
}
placed_cell = (10 * 80 + 20) * 2

seen = None
deadline = time.time() + 25
while time.time() < deadline:
    seen = screen()
    if seen:
        rows, data = seen
        if all(rows[r].startswith(text) for r, text in expected.items()) \
                and rows[10][20:26] == "Words!" and data[placed_cell + 1] == 14:
            break
    time.sleep(0.5)
else:
    print("FAIL: the expected words never all appeared")
    if seen:
        rows, _ = seen
        for r in sorted(expected):
            print(f"  row {r}: {rows[r][:40]!r} (expected {expected[r]!r})")
        print(f"  row 10, columns 20-25: {rows[10][20:26]!r} (expected 'Words!')")
    finish(False)

rows, data = seen
for r in sorted(expected):
    print(f"row {r}: {rows[r][:len(expected[r]) + 8]!r}")
print(f"row 10: {rows[10][16:32]!r} with color byte {data[placed_cell + 1]} at the placed word")
finish(True)
PYEOF
