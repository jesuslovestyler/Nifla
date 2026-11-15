#!/bin/sh
# Stone 16 proof: a disk. The script makes a scratch disk
# image — 8 MiB, all blank except sector 4, which holds a
# marker — and boots bare-examples/nifla-disk.nifla on it
# TWICE, with the image attached to the primary IDE channel
# as its master drive (QEMU's default attachment for
# -drive if=ide,index=0). The bare program speaks ATA PIO
# to it through the disk tools. VGA readback checks:
#
#   both boots, row 0: the marker sector's words,
#     "DISK MARKER SECTOR" — the read worked.
#   both boots, row 1: "sectors on this disk: 16384" —
#     disksectors() agrees with the image the script made.
#   boot 1, row 3: "WROTE - and read it back" — the program
#     wrote its message and pattern to sector 9, read the
#     sector back, and found them.
#   boot 2, row 2: "NIFLA WAS HERE", and row 3:
#     "FOUND - it persisted" — a fresh boot, a fresh machine,
#     and the message is still on the disk.
#
# SAFETY: the only disk ever touched is the scratch image
# this script creates in its own temp folder and deletes
# afterwards. Nothing else is attached, ever.
#
# Prints PASS or FAIL. QEMU is the bench machine's extracted
# QEMU 10 (~/qemu10-root), as in run-bare.sh; set QEMU to a
# plain qemu-system-x86_64 command line instead if one is
# installed (it is invoked with -kernel, -drive, -display,
# -nic, and -monitor appended).

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null' EXIT

ELF="$WORK/nifla-disk.elf"
if ! ./niflac --bare bare-examples/nifla-disk.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
    echo "FAIL: niflac --bare refused or failed:"
    cat "$WORK/build.txt"
    exit 1
fi
echo "Built the bare binary:"
cat "$WORK/build.txt"

IMG="$WORK/scratch-disk.img"
python3 - "$IMG" <<'PYEOF'
import sys

path = sys.argv[1]
image = bytearray(8 * 1024 * 1024)
marker = b"DISK MARKER SECTOR"
image[4 * 512:4 * 512 + len(marker)] = marker
with open(path, "wb") as f:
    f.write(image)
print("Made the scratch disk: 8 MiB, marker at sector 4, sector 9 blank.")
PYEOF

boot() {
    # $1 = boot number; echoes nothing; the screen lands in
    # $WORK/screen-$1.txt as four rows of text.
    SOCK="$WORK/monitor-$1.sock"
    if [ -n "${QEMU:-}" ]; then
        # A ready-made QEMU command (words are split on purpose).
        # shellcheck disable=SC2086
        $QEMU -kernel "$ELF" -drive file="$IMG",format=raw,if=ide,index=0 \
            -display none -nic none \
            -monitor "unix:$SOCK,server,nowait" &
        QEMU_PID=$!
    elif [ -x "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" ]; then
        "$HOME/qemu10-root/usr/lib64/ld-linux-x86-64.so.2" \
            --library-path "$HOME/qemu10-root/usr/lib/x86_64-linux-gnu:$HOME/qemu10-root/lib/x86_64-linux-gnu" \
            "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" \
            -kernel "$ELF" -drive file="$IMG",format=raw,if=ide,index=0 \
            -display none -nic none \
            -monitor "unix:$SOCK,server,nowait" \
            -L "$HOME/qemu10-root/usr/share/qemu" \
            -L "$HOME/qemu10-root/usr/share/seabios" \
            > "$WORK/qemu-$1.txt" 2>&1 &
        QEMU_PID=$!
    else
        echo "FAIL: no QEMU found (looked for ~/qemu10-root; set QEMU to a qemu-system-x86_64 command)"
        exit 1
    fi
    python3 - "$SOCK" "$WORK/screen-$1.txt" <<'PYEOF'
import re
import socket
import sys
import time

sock_path, out_path = sys.argv[1], sys.argv[2]

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
    global greeted
    try:
        if not greeted:
            read_until_prompt()
            greeted = True
        sock.sendall(b"xp /640bx 0xb8000\n")
        out = read_until_prompt()
    except (MonitorQuiet, OSError):
        return None
    data = []
    for line in out.splitlines():
        match = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if match:
            data += [int(part, 16) for part in match.group(1).split()]
    if len(data) < 640:
        return None
    chars = [chr(data[i]) if 32 <= data[i] < 127 else " " for i in range(0, 640, 2)]
    return ["".join(chars[r * 80:(r + 1) * 80]) for r in range(4)]


rows = None
deadline = time.time() + 25
while time.time() < deadline:
    rows = screen_rows()
    if rows and rows[3].startswith(("WROTE", "FOUND", "WRITE")):
        break
    time.sleep(0.5)

try:
    sock.sendall(b"quit\n")
    sock.close()
except OSError:
    pass

if rows is None:
    print("FAIL: the screen never became readable")
    sys.exit(1)
with open(out_path, "w") as f:
    f.write("\n".join(rows))
print("screen read")
PYEOF
    wait "$QEMU_PID" 2>/dev/null
    QEMU_PID=""
}

boot 1
echo "boot 1 screen:"
cat "$WORK/screen-1.txt"
boot 2
echo "boot 2 screen:"
cat "$WORK/screen-2.txt"

fail=0
check() {
    # $1 = boot, $2 = row, $3 = expected prefix
    line=$(sed -n "$(($2 + 1))p" "$WORK/screen-$1.txt")
    case "$line" in
        "$3"*) ;;
        *)
            echo "FAIL: boot $1 row $2 should begin '$3' but is: $line"
            fail=1
            ;;
    esac
}
check 1 0 "DISK MARKER SECTOR"
check 1 1 "sectors on this disk: 16384"
check 1 3 "WROTE - and read it back"
check 2 0 "DISK MARKER SECTOR"
check 2 1 "sectors on this disk: 16384"
check 2 2 "NIFLA WAS HERE"
check 2 3 "FOUND - it persisted"

if [ "$fail" -eq 0 ]; then
    echo "PASS nifla-disk (bare metal: sectors read and written on a real disk image, persisting across boots)"
else
    exit 1
fi
