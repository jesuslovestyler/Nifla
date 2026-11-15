#!/bin/sh
# Stone 23 proof: the ARM door. Four parts:
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
#      without '--bare', '--arm' beside '--guest', and
#      '--arm' beside '--video'.
#
#   3. The target's honest limits, refused in plain words:
#      a floor block and a disk tool in an ARM build
#      (Stone 24's work, and the virt machine's missing
#      ATA disk).
#
#   4. The x86 bare road still builds its founding example
#      (its full behavior proof is run-bare.sh and the
#      per-feature scripts; this part only keeps the road
#      open beside the new one).
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

# --- Part 1: build and boot --------------------------------
./niflac --bare --arm bare-examples/nifla-arm.nifla -o "$WORK/nifla-arm.elf" >/dev/null \
    || fail "the ARM example did not compile."
[ -f "$WORK/nifla-arm.elf" ] || fail "the ARM build left no binary behind."

QEMU="$QEMU" python3 - "$WORK/nifla-arm.elf" >"$WORK/serial.txt" <<'PYEOF' || fail "the serial drive failed."
import os, socket, subprocess, sys, time
elf = sys.argv[1]
qemu = os.environ["QEMU"]
ser_path, mon_path = elf + ".ser.sock", elf + ".mon.sock"
for p in (ser_path, mon_path):
    try: os.unlink(p)
    except FileNotFoundError: pass
proc = subprocess.Popen([qemu, "-machine", "virt", "-cpu", "cortex-a57",
    "-m", "128", "-nic", "none", "-kernel", elf, "-display", "none",
    "-serial", "unix:" + ser_path + ",server,nowait",
    "-monitor", "unix:" + mon_path + ",server,nowait"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
    mon.sendall(b"system_reset\n")
    ser.settimeout(0.2)
    data = b""
    deadline = time.time() + 25
    sent = False
    while time.time() < deadline:
        if not sent and b"Send a key" in data:
            ser.sendall(b"z")
            sent = True
        if sent and b"Echo:" in data:
            break
        try:
            chunk = ser.recv(4096)
            if chunk:
                data += chunk
        except socket.timeout:
            pass
finally:
    proc.terminate()
sys.stdout.write(data.decode("utf-8", "replace"))
PYEOF

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
expect_refusal "not stood up on the ARM target" --bare --arm --video 1024x768x32 bare-examples/nifla-arm.nifla -o "$WORK/x.elf"

# --- Part 3: the target's honest limits --------------------
cat >"$WORK/floor.nifla" <<'EOF'
let total = floor {
    mov rax, 1
}
say total
EOF
expect_refusal "Floor blocks are not stood up on the ARM target yet" --bare --arm "$WORK/floor.nifla" -o "$WORK/x.elf"
cat >"$WORK/disk.nifla" <<'EOF'
say disksectors()
EOF
expect_refusal "The disk tools are not stood up on the ARM target" --bare --arm "$WORK/disk.nifla" -o "$WORK/x.elf"

# --- Part 4: the x86 road still builds ----------------------
./niflac --bare bare-examples/nifla-bare.nifla -o "$WORK/nifla-bare-x86.elf" >/dev/null \
    || fail "the x86 bare build broke beside the ARM door."

echo "run-bare-arm: PASS — the ARM example greeted over the serial line, reckoned, read the machine's memory from its device tree, watched its ticks advance, and echoed the key; the flag and the target's limits refuse in plain words; the x86 road still builds."
