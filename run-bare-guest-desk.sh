#!/bin/bash
# The guest's desk, handed things — the standing proof for
# what Cardnull OS 2's Stone 10 measured. The guest
# (bare-examples/nifla-guest-desk.nifla) is handed a piece
# of text and a block of bytes in its main body, a
# function's own handed words passed onward to its floor,
# and a line of text handed with numbers to a small
# painter; it must receive every desk whole and hand back
# one reckoned number over them all (5 * 10000 + 64 * 100
# + 495 = 56895), and the painted line must stand on the
# host's screen. The host is the Stone 17 example host,
# unmodified; the guest rides a scratch disk image exactly
# as in run-bare-guest.sh.
#
# SAFETY: the only disk ever attached is the scratch image
# this script creates in its own scratch folder.
#
# Prints PASS and exits 0 when every read-back matches.

set -u
cd "$(dirname "$0")"

QEMU_DIR="$HOME/qemu10-root"
QEMU="$QEMU_DIR/usr/bin/qemu-system-x86_64"
LOADER="$QEMU_DIR/usr/lib64/ld-linux-x86-64.so.2"
LIBPATH="$QEMU_DIR/usr/lib/x86_64-linux-gnu:$QEMU_DIR/lib/x86_64-linux-gnu"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "FAIL: $1"
    exit 1
}

./niflac --bare --guest bare-examples/nifla-guest-desk.nifla -o "$WORK/guest.bin" >/dev/null || fail "the guest didn't build"
./niflac --bare bare-examples/nifla-host.nifla -o "$WORK/host.elf" >/dev/null || fail "the host didn't build"

python3 - "$WORK" <<'PYEOF'
import struct, sys
work = sys.argv[1]
guest = open(work + "/guest.bin", "rb").read()
h = 0xcbf29ce484222325
for b in guest:
    h ^= b
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
image = bytearray(1024 * 1024)
image[32 * 512:32 * 512 + 24] = struct.pack("<QQQ", 40, len(guest), h)
image[40 * 512:40 * 512 + len(guest)] = guest
open(work + "/disk.img", "wb").write(image)
print(f"Laid the guest: {len(guest)} bytes at sector 40, card at sector 32.")
PYEOF

SOCK="$WORK/mon.sock"
"$LOADER" --library-path "$LIBPATH" "$QEMU" \
    -kernel "$WORK/host.elf" \
    -drive file="$WORK/disk.img",format=raw,if=ide,index=0 \
    -display none -nic none \
    -monitor unix:"$SOCK",server,nowait \
    -L "$QEMU_DIR/usr/share/qemu" -L "$QEMU_DIR/usr/share/seabios" \
    >/dev/null 2>&1 &
QPID=$!

python3 - "$SOCK" "$WORK/rows.txt" <<'PYEOF'
import re, socket, sys, time
sock_path, out_path = sys.argv[1], sys.argv[2]
deadline = time.time() + 25
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
        time.sleep(0.1)
if sock is None:
    open(out_path, "w").write("")
    sys.exit(0)
sock.settimeout(5)
buf = b""
def until_prompt():
    global buf
    while b"(qemu)" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise IOError("monitor closed")
        buf += chunk
    out, buf = buf.decode(errors="replace"), b""
    return out
try:
    until_prompt()
except IOError:
    open(out_path, "w").write("")
    sys.exit(0)
def rows():
    sock.sendall(b"xp /800bx 0xb8000\n")
    out = until_prompt()
    data = []
    for line in out.splitlines():
        m = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if m:
            data += [int(p, 16) for p in m.group(1).split()]
    if len(data) < 800:
        return None
    return ["".join(chr(data[(r * 80 + c) * 2]) if 32 <= data[(r * 80 + c) * 2] < 127 else " " for c in range(80)) for r in range(5)]
found = None
while time.time() < deadline:
    try:
        r = rows()
    except IOError:
        break
    if r and r[1].startswith("HOST: back again"):
        found = r
        break
    time.sleep(0.25)
if found is None:
    found = r if 'r' in dir() and r else ["", "", "", "", ""]
open(out_path, "w").write("\n".join(found))
try:
    sock.sendall(b"quit\n")
    sock.close()
except OSError:
    pass
PYEOF
wait "$QPID" 2>/dev/null

echo "screen:"
cat "$WORK/rows.txt"
echo
grep -q "HOST: back again - the guest gave 56895" "$WORK/rows.txt" \
    || fail "the guest's reckoned number is not 56895 — a handed desk arrived less than whole"
grep -q "    HANDED TEXT WORKS" "$WORK/rows.txt" \
    || fail "the line the guest was handed to paint is not on the screen"

echo "PASS nifla-guest-desk (bare metal: a guest's floor blocks handed text and bytes receive them whole — pointer, length, and letters)"
