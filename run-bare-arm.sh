#!/bin/sh
# Stone 23 proof: the ARM door — and Stone 24: floor and
# face on ARM. Six parts:
#
#   1. bare-examples/nifla-arm.nifla compiles with
#      `niflac --bare --arm` and boots under
#      qemu-system-aarch64 on the virt machine; what it
#      says over the PL011 serial line must be exactly the
#      expected greeting and reckonings, the ticks must
#      advance, and the key the proof sends ('z') must be
#      echoed.
#
#   2. The flag's own refusals, in plain words: '--arm'
#      without '--bare', '--arm' beside '--guest', and a
#      '--video' depth the ARM screen does not speak.
#
#   3. The target's honest limit, refused in plain
#      words: a disk tool in an ARM build (the virt
#      machine has no ATA disk of the kind the x86 road
#      speaks to).
#
#   4. The x86 bare road still builds its founding
#      example (its full behavior proof is run-bare.sh
#      and the per-feature scripts; this part only keeps
#      the road open beside the new one).
#
#   5. (Stone 24) bare-examples/nifla-arm-floor.nifla:
#      floor blocks holding aarch64 assembly do real work
#      over the desk — handed numbers added, a handed
#      text's bytes walked and summed — and say their
#      answers over the serial line.
#
#   6. (Stone 24) bare-examples/nifla-arm-screen.nifla,
#      built with '--video 640x480x32': the kernel sets
#      up the machine's ramfb picture screen, a floor
#      block paints it (red left, blue right, a white
#      square), and a screendump's sampled pixels must
#      show the painting.
#
# The serial drive needs care: bytes sent before a client
# is listening are lost, so the driver below connects to
# both the serial line and the monitor, then resets the
# machine — the guest starts with its listener attached.
set -u
cd "$(dirname "$0")"
fail() { echo "run-bare-arm: $1"; exit 1; }

QEMU=""
if [ -n "${QEMU_ARM:-}" ]; then
    QEMU="$QEMU_ARM"
elif [ -x "$HOME/qemu-arm-root/usr/bin/qemu-system-aarch64" ]; then
    QEMU="$HOME/qemu-arm-root/usr/bin/qemu-system-aarch64"
    export LD_LIBRARY_PATH="$HOME/qemu-arm-root/usr/lib/x86_64-linux-gnu:$HOME/qemu-arm-root/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
elif command -v qemu-system-aarch64 >/dev/null 2>&1; then
    QEMU="$(command -v qemu-system-aarch64)"
fi
[ -n "$QEMU" ] || fail "qemu-system-aarch64 was not found (looked in \$QEMU_ARM, ~/qemu-arm-root, and the PATH) — the ARM proof cannot run on this bench."
command -v python3 >/dev/null 2>&1 || fail "python3 was not found — the serial drive needs it."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The shared drive: boot an ELF, gather its serial words
# until $2 appears (or the deadline passes), and — when
# $3 names a file — take a screendump into it. ARM_VIDEO=1
# in the environment adds the ramfb device.
cat >"$WORK/drive.py" <<'PYEOF'
import os, socket, subprocess, sys, time
elf, waitfor = sys.argv[1], sys.argv[2]
ppm = sys.argv[3] if len(sys.argv) > 3 else None
ser_path, mon_path = elf + ".ser.sock", elf + ".mon.sock"
for p in (ser_path, mon_path):
    try: os.unlink(p)
    except FileNotFoundError: pass
args = [os.environ["QEMU"], "-machine", "virt", "-cpu", "cortex-a57",
    "-m", "128", "-nic", "none", "-kernel", elf, "-display", "none",
    "-serial", "unix:" + ser_path + ",server,nowait",
    "-monitor", "unix:" + mon_path + ",server,nowait"]
if os.environ.get("ARM_VIDEO") == "1":
    args += ["-device", "ramfb"]
proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def connect(path):
    for _ in range(200):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            return s
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("no socket " + path)
try:
    ser = connect(ser_path)
    mon = connect(mon_path)
    def moncmd(c):
        mon.sendall(c.encode() + b"\n")
        time.sleep(0.5)
        mon.settimeout(0.3)
        try:
            while mon.recv(65536):
                pass
        except socket.timeout:
            pass
    moncmd("system_reset")
    ser.settimeout(0.2)
    data = b""
    deadline = time.time() + 25
    while time.time() < deadline:
        if b"Send a key" in data and b"Echo:" not in data:
            try: ser.sendall(b"z")
            except OSError: pass
        if waitfor.encode() in data:
            break
        try:
            chunk = ser.recv(4096)
            if chunk:
                data += chunk
        except socket.timeout:
            pass
    if ppm:
        time.sleep(1)
        moncmd("screendump " + ppm)
finally:
    proc.terminate()
sys.stdout.write(data.decode("utf-8", "replace"))
PYEOF

drive() {
    # $1 = elf, $2 = words to wait for, $3 = screendump (optional)
    QEMU="$QEMU" python3 "$WORK/drive.py" "$1" "$2" ${3:+"$3"}
}

# --- Part 1: build and boot --------------------------------
./niflac --bare --arm bare-examples/nifla-arm.nifla -o "$WORK/nifla-arm.elf" >/dev/null \
    || fail "the ARM example did not compile."
[ -f "$WORK/nifla-arm.elf" ] || fail "the ARM build left no binary behind."
drive "$WORK/nifla-arm.elf" "Echo: z" >"$WORK/serial.txt" || fail "the serial drive failed."

for line in \
    "Nifla stands on ARM." \
    "Memory: 134217728" \
    "Hello, virt machine." \
    "One to ten adds to 55" \
    "Square of nine is 81" \
    "A hundred divided by seven is 14" \
    "Below zero: -5" \
    "Block: 72 105" \
    "Words match." \
    "Ticks advance." \
    "Send a key and I will echo it." \
    "Echo: z"
do
    grep -Fqx "$line" "$WORK/serial.txt" || fail "the serial line never said: $line
What it said:
$(cat "$WORK/serial.txt")"
done
[ "$(grep -Fc 'Again.' "$WORK/serial.txt")" = "3" ] \
    || fail "the repeat did not say 'Again.' three times."

# --- Part 2: the flag's refusals ---------------------------
expect_refusal() {
    # $1 = a few words the refusal must carry; rest = the build
    words="$1"; shift
    out="$(./niflac "$@" 2>&1)" && fail "a build that must be refused was not: niflac $*"
    case "$out" in
        *"$words"*) : ;;
        *) fail "the refusal for 'niflac $*' did not say '$words'. It said: $out" ;;
    esac
}
expect_refusal "add '--bare'" --arm bare-examples/nifla-arm.nifla -o "$WORK/x.elf"
expect_refusal "not stood up on the ARM target" --bare --arm --guest bare-examples/nifla-arm.nifla -o "$WORK/x.bin"
expect_refusal "speaks 32-bit color" --bare --arm --video 640x480x24 bare-examples/nifla-arm.nifla -o "$WORK/x.elf"

# --- Part 3: the target's honest limit ---------------------
cat >"$WORK/disk.nifla" <<'EOF'
say disksectors()
EOF
expect_refusal "The disk tools are not stood up on the ARM target" --bare --arm "$WORK/disk.nifla" -o "$WORK/x.elf"

# --- Part 4: the x86 road still builds ----------------------
./niflac --bare bare-examples/nifla-bare.nifla -o "$WORK/nifla-bare-x86.elf" >/dev/null \
    || fail "the x86 bare build broke beside the ARM door."

# --- Part 5: the floor on ARM -------------------------------
./niflac --bare --arm bare-examples/nifla-arm-floor.nifla -o "$WORK/nifla-arm-floor.elf" >/dev/null \
    || fail "the ARM floor example did not compile."
drive "$WORK/nifla-arm-floor.elf" "letters add to" >"$WORK/floor.txt" || fail "the floor drive failed."
grep -Fqx "The floor reckons 46" "$WORK/floor.txt" \
    || fail "the floor's reckoning was not said. What was said:
$(cat "$WORK/floor.txt")"
grep -Fqx "The letters add to 394" "$WORK/floor.txt" \
    || fail "the floor's letter sum was not said. What was said:
$(cat "$WORK/floor.txt")"

# --- Part 6: the face on ARM --------------------------------
./niflac --bare --arm --video 640x480x32 bare-examples/nifla-arm-screen.nifla -o "$WORK/nifla-arm-screen.elf" >/dev/null \
    || fail "the ARM screen example did not compile."
ARM_VIDEO=1 drive "$WORK/nifla-arm-screen.elf" "screen is painted" "$WORK/screen.ppm" >"$WORK/screen.txt" \
    || fail "the screen drive failed."
grep -Fqx "The screen is painted." "$WORK/screen.txt" \
    || fail "the screen program never said its line. What was said:
$(cat "$WORK/screen.txt")"
[ -f "$WORK/screen.ppm" ] || fail "no screendump was taken."
python3 - "$WORK/screen.ppm" <<'PYEOF' || fail "the painted pixels were not as expected."
import sys
with open(sys.argv[1], "rb") as f:
    raw = f.read()
parts = raw.split(b"\n", 3)
assert parts[0] == b"P6", "not a PPM"
w, h = map(int, parts[1].split())
pix = parts[3]
def px(x, y):
    i = (y * w + x) * 3
    return tuple(pix[i:i + 3])
checks = {(10, 10): (255, 0, 0), (630, 10): (0, 0, 255),
          (150, 150): (255, 255, 255), (400, 300): (0, 0, 255)}
for (x, y), want in checks.items():
    got = px(x, y)
    assert got == want, f"pixel ({x},{y}) is {got}, expected {want}"
print(f"screendump {w}x{h}: pixels as painted")
PYEOF

echo "run-bare-arm: PASS — the ARM example greeted over the serial line, reckoned, read the machine's memory from its device tree, watched its ticks advance, and echoed the key; the flag and the target's limits refuse in plain words; the x86 road still builds; floor blocks did real work over the desk; and the ramfb screen shows the floor's painting."
