#!/bin/sh
# Stone 18 proof: annotations on bare metal. Three parts:
#
#   1. bare-examples/nifla-kinds.nifla — an annotated bare
#      program (a marked variable, marked parameters, a
#      promised give) — compiles with `niflac --bare` and
#      boots in QEMU; VGA readback must show:
#        row 0: "kinds"   — a marked text variable, said
#        row 1: "42"      — an annotated function's answer
#
#   2. A bare build whose 'let' annotation provably
#      mismatches its value must be refused before building,
#      in the annotation's plain words.
#
#   3. A bare build marking a parameter with a kind bare
#      metal can't hold (a list) must be refused in plain
#      words — the BareValidator keeps refusing what bare
#      cannot do, annotation or not.
#
#   4. A bare build with a provably negative repeat count
#      must be refused by the shared checker, as on the
#      hosted side.
#
#   5. (Stone 19) A bare build using 'nothing' must be
#      refused in plain words — absence stands apart on
#      bare metal: a bare value is a machine word with one
#      shape, and the empty value has no word to be.
#
#   6. (Stone 19) A bare build with a 'maybe' annotation
#      must be refused the same way — a kind bare metal
#      can't hold.
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

# --- parts 2–4: the refusals --------------------------------

cat > "$WORK/mismatch.nifla" <<'EOF'
let n: number = "hello"
say n
EOF
if ./niflac --bare "$WORK/mismatch.nifla" -o "$WORK/mismatch.elf" > "$WORK/mismatch.txt" 2>&1; then
    echo "FAIL: the mismatched annotation was allowed to build for bare metal"
    exit 1
fi
if ! grep -q "'n' is marked as a number by its annotation, but this value is some text" "$WORK/mismatch.txt"; then
    echo "FAIL: the bare mismatch refusal said the wrong words:"
    cat "$WORK/mismatch.txt"
    exit 1
fi
echo "Refused, as expected (annotation mismatch): $(cat "$WORK/mismatch.txt")"

cat > "$WORK/listkind.nifla" <<'EOF'
make f(a: list) {
    give a
}
say "never"
EOF
if ./niflac --bare "$WORK/listkind.nifla" -o "$WORK/listkind.elf" > "$WORK/listkind.txt" 2>&1; then
    echo "FAIL: a list annotation was allowed to build for bare metal"
    exit 1
fi
if ! grep -q "Bare metal can't hold a list" "$WORK/listkind.txt"; then
    echo "FAIL: the bare list-annotation refusal said the wrong words:"
    cat "$WORK/listkind.txt"
    exit 1
fi
echo "Refused, as expected (a kind bare can't hold): $(cat "$WORK/listkind.txt")"

cat > "$WORK/repeatneg.nifla" <<'EOF'
repeat -1 {
    say "never"
}
EOF
if ./niflac --bare "$WORK/repeatneg.nifla" -o "$WORK/repeatneg.elf" > "$WORK/repeatneg.txt" 2>&1; then
    echo "FAIL: a negative repeat count was allowed to build for bare metal"
    exit 1
fi
if ! grep -q "'repeat' was told to run -1 times" "$WORK/repeatneg.txt"; then
    echo "FAIL: the bare repeat refusal said the wrong words:"
    cat "$WORK/repeatneg.txt"
    exit 1
fi
echo "Refused, as expected (negative repeat): $(cat "$WORK/repeatneg.txt")"

cat > "$WORK/nothing.nifla" <<'EOF'
let x = nothing
say "never"
EOF
if ./niflac --bare "$WORK/nothing.nifla" -o "$WORK/nothing.elf" > "$WORK/nothing.txt" 2>&1; then
    echo "FAIL: 'nothing' was allowed to build for bare metal"
    exit 1
fi
if ! grep -q "Bare metal has no 'nothing'" "$WORK/nothing.txt"; then
    echo "FAIL: the bare nothing refusal said the wrong words:"
    cat "$WORK/nothing.txt"
    exit 1
fi
echo "Refused, as expected (nothing on bare metal): $(cat "$WORK/nothing.txt")"

cat > "$WORK/maybekind.nifla" <<'EOF'
let x: maybe number = 5
say x
EOF
if ./niflac --bare "$WORK/maybekind.nifla" -o "$WORK/maybekind.elf" > "$WORK/maybekind.txt" 2>&1; then
    echo "FAIL: a 'maybe' annotation was allowed to build for bare metal"
    exit 1
fi
if ! grep -q "Bare metal can't hold a number or nothing" "$WORK/maybekind.txt"; then
    echo "FAIL: the bare maybe-annotation refusal said the wrong words:"
    cat "$WORK/maybekind.txt"
    exit 1
fi
echo "Refused, as expected (a maybe kind bare can't hold): $(cat "$WORK/maybekind.txt")"

# --- part 1: the annotated program boots ---------------------

ELF="$WORK/nifla-kinds.elf"
if ! ./niflac --bare bare-examples/nifla-kinds.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
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
    """The whole text screen: 25 rows of text."""
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
    return rows


def finish(ok):
    try:
        sock.sendall(b"quit\n")
        sock.close()
    except OSError:
        pass
    if ok:
        print("PASS nifla-kinds (bare metal: annotations checked, the annotated program runs)")
        sys.exit(0)
    sys.exit(1)


expected = {
    0: "kinds",
    1: "42",
}

seen = None
deadline = time.time() + 25
while time.time() < deadline:
    rows = screen()
    if rows is not None:
        seen = rows
        if all(rows[r].rstrip() == text for r, text in expected.items()):
            finish(True)
    time.sleep(0.3)

print("FAIL: the screen never showed the expected lines; last seen:")
if seen is not None:
    for r in range(5):
        print("  row %d: %r" % (r, seen[r].rstrip()))
finish(False)
PYEOF
