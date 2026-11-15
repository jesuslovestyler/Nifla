#!/bin/bash
# The Stone 17 proof: a guest comes through the door.
#
# The script builds the guest (niflac --bare --guest — a
# flat image linked for the doorstep at 2 MiB) and the host
# (niflac --bare), then lays the guest on a scratch disk
# image: a card at sector 32 (start sector, length, and the
# guest's FNV-1a checksum, reckoned here over the guest's
# file) and the image itself at sector 40. It boots the
# host twice:
#
#   Boot 1 (the image as laid): the screen must show, in
#   order — the host's line, the guest's three lines (it
#   read the host's gift off the desk, and its words
#   continue the host's page), and the host's line again,
#   reporting the guest's parting number. Order on one
#   shared page is the proof that control truly passed
#   over and came back.
#
#   Boot 2 (one byte of the guest flipped on the image):
#   the checksum no longer matches the card, and the host
#   must refuse — on screen — and never run the guest: no
#   guest line may appear.
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

./niflac --bare --guest bare-examples/nifla-guest.nifla -o "$WORK/guest.bin" >/dev/null || fail "the guest didn't build"
./niflac --bare bare-examples/nifla-host.nifla -o "$WORK/host.elf" >/dev/null || fail "the host didn't build"

# Lay the guest on the image, and reckon its checksum.
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
# The tampered twin: one byte of the guest flipped.
image[40 * 512 + 100] ^= 0xFF
open(work + "/disk-tampered.img", "wb").write(image)
print(f"Laid the guest: {len(guest)} bytes at sector 40, card at sector 32 (and a tampered twin).")
PYEOF

# Boots the host against the given image; leaves the first
# five screen rows in $WORK/rows.txt.
boot() {
    local img="$1"
    local sock="$WORK/mon.sock"
    rm -f "$sock"
    "$LOADER" --library-path "$LIBPATH" "$QEMU" \
        -kernel "$WORK/host.elf" \
        -drive file="$img",format=raw,if=ide,index=0 \
        -display none -nic none \
        -monitor unix:"$sock",server,nowait \
        -L "$QEMU_DIR/usr/share/qemu" -L "$QEMU_DIR/usr/share/seabios" \
        >/dev/null 2>&1 &
    local qpid=$!
    python3 - "$sock" "$WORK/rows.txt" <<'PYEOF'
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
    print("screen read\nthe QEMU monitor never opened")
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
    if r and (r[4].startswith("HOST: back again") or r[1].startswith("HOST: the guest on disk is not whole")):
        found = r
        break
    time.sleep(0.25)
if found is None:
    found = r if 'r' in dir() and r else ["", "", "", "", ""]
print("screen read")
open(out_path, "w").write("\n".join(found))
try:
    sock.sendall(b"quit\n")
    sock.close()
except OSError:
    pass
PYEOF
    wait "$qpid" 2>/dev/null
}

expect_row() {
    local file="$1" idx="$2" want="$3" bootname="$4"
    local got
    got="$(sed -n "$((idx + 1))p" "$file")"
    case "$got" in
        "$want"*) ;;
        *) fail "$bootname row $idx should begin '$want' but is: $got" ;;
    esac
}

boot "$WORK/disk.img"
echo "boot 1 screen (guest whole):"
cat "$WORK/rows.txt"
echo
expect_row "$WORK/rows.txt" 0 "HOST: before the guest" "boot 1"
expect_row "$WORK/rows.txt" 1 "GUEST: I am running" "boot 1"
expect_row "$WORK/rows.txt" 2 "GUEST: the host sent 7" "boot 1"
expect_row "$WORK/rows.txt" 3 "GUEST: twice the gift is 14" "boot 1"
expect_row "$WORK/rows.txt" 4 "HOST: back again - the guest gave 42" "boot 1"

boot "$WORK/disk-tampered.img"
echo "boot 2 screen (guest tampered):"
cat "$WORK/rows.txt"
echo
expect_row "$WORK/rows.txt" 0 "HOST: before the guest" "boot 2"
expect_row "$WORK/rows.txt" 1 "HOST: the guest on disk is not whole - I will not run it" "boot 2"
if grep -q "GUEST:" "$WORK/rows.txt"; then
    fail "boot 2 ran the tampered guest — a GUEST line is on the screen"
fi

echo "PASS nifla-guest (bare metal: a guest loaded, checksum-verified, called, and returned from; a tampered guest refused)"
