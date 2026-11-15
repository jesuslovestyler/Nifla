#!/bin/sh
# Stone 11 proof: first bare metal. Compiles
# bare-examples/nifla-bare.nifla with `niflac --bare`, boots
# the binary in QEMU with no display, and reads the emulated
# screen's memory (the VGA text buffer at 0xB8000) back
# through the QEMU monitor: every second byte there is a
# letter of the screen's first two rows. The rows must begin
# with the lines of bare-examples/nifla-bare.screen — a
# beginning, not the whole row, because the BIOS writes its
# own banner first and the program overwrites it from the
# first cell; what the BIOS left beyond the program's words
# is not the program's doing.
#
# Prints PASS or FAIL. QEMU is the bench machine's extracted
# QEMU 10 (~/qemu10-root), run through its own loader; set
# QEMU to a plain qemu-system-x86_64 command line instead if
# one is installed.

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null' EXIT

ELF="$WORK/nifla-bare.elf"
if ! ./niflac --bare bare-examples/nifla-bare.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
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

python3 - "$SOCK" bare-examples/nifla-bare.screen <<'PYEOF'
import re
import socket
import sys
import time

sock_path, screen_path = sys.argv[1], sys.argv[2]
expected = [line for line in open(screen_path).read().splitlines()]

# Connect to the monitor (QEMU may take a moment to open it).
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
            # The monitor's greeting, prompt and all, is read
            # once; after that, each answer ends with the next
            # prompt, so nothing is ever left waiting.
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


# The machine boots, the BIOS banner comes and goes, and the
# program writes and halts; poll until the words are there.
deadline = time.time() + 25
rows = None
while time.time() < deadline:
    rows = screen_rows()
    if rows and all(rows[i].startswith(expected[i]) for i in range(len(expected))):
        break
    time.sleep(0.5)

try:
    sock.sendall(b"quit\n")
    sock.close()
except OSError:
    pass

if rows and all(rows[i].startswith(expected[i]) for i in range(len(expected))):
    for i, line in enumerate(expected):
        print(f"row {i + 1} begins: {line!r}")
    print("PASS nifla-bare (bare metal: the words are on the emulated screen)")
    sys.exit(0)
print("FAIL: the expected words never appeared on the emulated screen")
print(f"expected rows to begin with: {expected!r}")
print(f"last rows read: {rows!r}")
sys.exit(1)
PYEOF
