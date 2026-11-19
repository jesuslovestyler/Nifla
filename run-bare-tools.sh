#!/bin/sh
# The bare tools proof: the hosted toolbox words on bare
# metal. Four parts:
#
#   1. (Stone 34) Compiles bare-examples/nifla-tools.nifla
#      with `niflac --bare`, boots the binary in QEMU with
#      no display, and reads the emulated screen's memory
#      (the VGA text buffer at 0xB8000) back through the
#      QEMU monitor: every second byte there is a letter of
#      the screen's rows. The rows must begin with the lines
#      of bare-examples/nifla-tools.screen — a beginning,
#      not the whole row, because the BIOS writes its own
#      banner first and the program overwrites it from the
#      first cell; what the BIOS left beyond the program's
#      words is not the program's doing. Each stone that
#      brings a word to bare metal adds its line to the
#      program and the screen file.
#
#   2. The same tools program built for the ARM door
#      (`niflac --bare --arm`) boots on QEMU's virt machine
#      and speaks every line over the serial line.
#
#   3. (Stone 39) The halt proof, x86: bare-examples/
#      nifla-tools-halt.nifla reads a text that is not a
#      number with `asnumber`; the machine must stop
#      before its next word can be said — the first line
#      stands on the screen and the last never does.
#
#   4. (Stone 39) The halt proof, ARM: the same program
#      over the serial line — the first line arrives and
#      the last never does.
#
# Prints PASS or FAIL. The x86 QEMU is the bench machine's
# extracted QEMU 10 (~/qemu10-root), run through its own
# loader; set QEMU to a plain qemu-system-x86_64 command
# line instead if one is installed. The ARM QEMU is found
# the way run-bare-arm.sh finds it ($QEMU_ARM,
# ~/qemu-arm-root, or the PATH).

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null' EXIT

ELF="$WORK/nifla-tools.elf"
if ! ./niflac --bare bare-examples/nifla-tools.nifla -o "$ELF" > "$WORK/build.txt" 2>&1; then
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

python3 - "$SOCK" bare-examples/nifla-tools.screen <<'PYEOF'
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
        sock.sendall(b"xp /1600bx 0xb8000\n")
        out = read_until_prompt()
    except (MonitorQuiet, OSError):
        return None
    data = []
    for line in out.splitlines():
        match = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if match:
            data += [int(part, 16) for part in match.group(1).split()]
    if len(data) < 1600:
        return None
    chars = [chr(data[i]) if 32 <= data[i] < 127 else " " for i in range(0, 1600, 2)]
    return ["".join(chars[i * 80:(i + 1) * 80]) for i in range(10)]


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
    print("PASS nifla-tools (bare metal: the toolbox words are on the emulated screen)")
    sys.exit(0)
print("FAIL: the expected words never appeared on the emulated screen")
print(f"expected rows to begin with: {expected!r}")
print(f"last rows read: {rows!r}")
sys.exit(1)
PYEOF
[ $? -eq 0 ] || exit 1
kill "$QEMU_PID" 2>/dev/null; QEMU_PID=""

# --- Part 2: the tools program on the ARM door --------------
QEMU_ARM_BIN=""
if [ -n "${QEMU_ARM:-}" ]; then
    QEMU_ARM_BIN="$QEMU_ARM"
elif [ -x "$HOME/qemu-arm-root/usr/bin/qemu-system-aarch64" ]; then
    QEMU_ARM_BIN="$HOME/qemu-arm-root/usr/bin/qemu-system-aarch64"
    export LD_LIBRARY_PATH="$HOME/qemu-arm-root/usr/lib/x86_64-linux-gnu:$HOME/qemu-arm-root/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
elif command -v qemu-system-aarch64 >/dev/null 2>&1; then
    QEMU_ARM_BIN="$(command -v qemu-system-aarch64)"
fi
[ -n "$QEMU_ARM_BIN" ] || { echo "FAIL: qemu-system-aarch64 was not found (looked in \$QEMU_ARM, ~/qemu-arm-root, and the PATH)"; exit 1; }

# The shared serial drive: boot an ELF on the virt machine,
# gather its serial words until $2 appears in them (or the
# deadline passes), and print what was gathered. Bytes sent
# before a client is listening are lost, so the drive
# connects first and then resets the machine.
cat >"$WORK/drive.py" <<'PYEOF'
import os, socket, subprocess, sys, time
elf, waitfor = sys.argv[1], sys.argv[2]
settle = float(sys.argv[3]) if len(sys.argv) > 3 else 0
ser_path, mon_path = elf + ".ser.sock", elf + ".mon.sock"
for p in (ser_path, mon_path):
    try: os.unlink(p)
    except FileNotFoundError: pass
args = [os.environ["QEMU_ARM_BIN"], "-machine", "virt", "-cpu", "cortex-a57",
    "-m", "128", "-nic", "none", "-kernel", elf, "-display", "none",
    "-serial", "unix:" + ser_path + ",server,nowait",
    "-monitor", "unix:" + mon_path + ",server,nowait"]
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
    mon.sendall(b"system_reset\n")
    time.sleep(0.5)
    mon.settimeout(0.3)
    try:
        while mon.recv(65536):
            pass
    except socket.timeout:
        pass
    ser.settimeout(0.2)
    data = b""
    deadline = time.time() + 25
    found_at = None
    while time.time() < deadline:
        if waitfor.encode() in data:
            if found_at is None:
                found_at = time.time()
            if time.time() - found_at >= settle:
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

drive_arm() {
    # $1 = elf, $2 = words to wait for, $3 = settle seconds
    QEMU_ARM_BIN="$QEMU_ARM_BIN" python3 "$WORK/drive.py" "$1" "$2" "$3"
}

ARM_ELF="$WORK/nifla-tools-arm.elf"
if ! ./niflac --bare --arm bare-examples/nifla-tools.nifla -o "$ARM_ELF" > "$WORK/build-arm.txt" 2>&1; then
    echo "FAIL: niflac --bare --arm refused or failed:"
    cat "$WORK/build-arm.txt"
    exit 1
fi
drive_arm "$ARM_ELF" "Bare tools" 0 >"$WORK/tools-serial.txt" || { echo "FAIL: the ARM serial drive failed"; exit 1; }
while IFS= read -r line; do
    grep -Fqx "$line" "$WORK/tools-serial.txt" || {
        echo "FAIL: the ARM serial line never said: $line"
        echo "What it said:"
        cat "$WORK/tools-serial.txt"
        exit 1
    }
done < bare-examples/nifla-tools.screen
echo "PASS nifla-tools on ARM (the toolbox words spoken over the serial line)"

# --- Part 3: the halt proof, x86 -----------------------------
HALT_ELF="$WORK/nifla-tools-halt.elf"
if ! ./niflac --bare bare-examples/nifla-tools-halt.nifla -o "$HALT_ELF" > "$WORK/build-halt.txt" 2>&1; then
    echo "FAIL: niflac --bare refused the halt program:"
    cat "$WORK/build-halt.txt"
    exit 1
fi
SOCK="$WORK/monitor-halt.sock"
if [ -n "${QEMU:-}" ]; then
    # shellcheck disable=SC2086
    $QEMU -kernel "$HALT_ELF" -display none -m 32 -nic none \
        -monitor "unix:$SOCK,server,nowait" &
    QEMU_PID=$!
else
    "$HOME/qemu10-root/usr/lib64/ld-linux-x86-64.so.2" \
        --library-path "$HOME/qemu10-root/usr/lib/x86_64-linux-gnu:$HOME/qemu10-root/lib/x86_64-linux-gnu" \
        "$HOME/qemu10-root/usr/bin/qemu-system-x86_64" \
        -kernel "$HALT_ELF" -display none -m 32 -nic none \
        -monitor "unix:$SOCK,server,nowait" \
        -L "$HOME/qemu10-root/usr/share/qemu" \
        -L "$HOME/qemu10-root/usr/share/seabios" \
        > "$WORK/qemu-halt.txt" 2>&1 &
    QEMU_PID=$!
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
    print("FAIL: the QEMU monitor never opened (halt proof)")
    sys.exit(1)
sock.settimeout(5)


class MonitorQuiet(Exception):
    pass


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
        sock.sendall(b"xp /1600bx 0xb8000\n")
        out = read_until_prompt()
    except (MonitorQuiet, OSError):
        return None
    data = []
    for line in out.splitlines():
        match = re.match(r"^[0-9a-f]+: ((?:0x[0-9a-f]{2} ?)+)$", line.strip())
        if match:
            data += [int(part, 16) for part in match.group(1).split()]
    if len(data) < 1600:
        return None
    chars = [chr(data[i]) if 32 <= data[i] < 127 else " " for i in range(0, 1600, 2)]
    return ["".join(chars[i * 80:(i + 1) * 80]) for i in range(10)]


# Wait for the first line to stand, then give the machine
# time to say more if it wrongly could, and read again:
# the reading must have stopped the machine, so the last
# line must never stand.
deadline = time.time() + 25
rows = None
while time.time() < deadline:
    rows = screen_rows()
    if rows and rows[0].startswith("Before the reading"):
        break
    time.sleep(0.5)
if not (rows and rows[0].startswith("Before the reading")):
    print("FAIL: the halt program's first line never stood on the screen")
    print(f"last rows read: {rows!r}")
    sys.exit(1)
time.sleep(3)
rows = screen_rows()

try:
    sock.sendall(b"quit\n")
    sock.close()
except OSError:
    pass

if rows is None:
    print("FAIL: the screen could not be read back (halt proof)")
    sys.exit(1)
if any(row.startswith("After the reading") for row in rows):
    print("FAIL: the machine read an unreadable text and kept going — 'After the reading' stands on the screen")
    sys.exit(1)
if any("Read:" in row for row in rows):
    print("FAIL: the reading answered instead of stopping the machine — a 'Read:' line stands on the screen")
    sys.exit(1)
print("PASS nifla-tools-halt (bare metal: an unreadable text stopped the machine before its next word)")
sys.exit(0)
PYEOF
[ $? -eq 0 ] || exit 1
kill "$QEMU_PID" 2>/dev/null; QEMU_PID=""

# --- Part 4: the halt proof, ARM ------------------------------
HALT_ARM_ELF="$WORK/nifla-tools-halt-arm.elf"
if ! ./niflac --bare --arm bare-examples/nifla-tools-halt.nifla -o "$HALT_ARM_ELF" > "$WORK/build-halt-arm.txt" 2>&1; then
    echo "FAIL: niflac --bare --arm refused the halt program:"
    cat "$WORK/build-halt-arm.txt"
    exit 1
fi
drive_arm "$HALT_ARM_ELF" "Before the reading" 4 >"$WORK/halt-serial.txt" || { echo "FAIL: the ARM serial drive failed (halt proof)"; exit 1; }
grep -Fqx "Before the reading" "$WORK/halt-serial.txt" || {
    echo "FAIL: the ARM halt program's first line never arrived"
    echo "What arrived:"
    cat "$WORK/halt-serial.txt"
    exit 1
}
if grep -Fq "After the reading" "$WORK/halt-serial.txt" || grep -Fq "Read:" "$WORK/halt-serial.txt"; then
    echo "FAIL: the ARM machine read an unreadable text and kept going"
    echo "What arrived:"
    cat "$WORK/halt-serial.txt"
    exit 1
fi
echo "PASS nifla-tools-halt on ARM (an unreadable text stopped the machine before its next word)"

echo "run-bare-tools: PASS — the toolbox words stand on both bare doors, and an unreadable text stops both machines."
