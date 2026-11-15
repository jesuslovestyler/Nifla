#!/bin/sh
# Stone 20 proof: feathers from the compiler.
#
# `niflac --bare --guest --feather` must emit a real
# .feather: the compiled guest program together with its
# plain-text card (the .feather format's shape — a card,
# a blank line, then the program's own bytes). This proof:
#
#   1. Builds bare-examples/nifla-guest.nifla two ways —
#      as a plain guest and as a feather — and checks the
#      feather with an independent reckoning (python3):
#      the card's first line, its name (the program's own
#      file name), its byte count against the program part
#      that follows the blank line, and its checksum
#      against a fresh FNV-1a-64 reckoning over that part.
#   2. Checks the program part is byte-for-byte the plain
#      guest build — the mode lays a card on the program;
#      it does not change the program. (The guest build
#      itself is booted and proven by run-bare-guest.sh;
#      the door that reads a whole .feather and runs it is
#      Cardnull OS 2's, proven in that repository.)
#   3. Checks the flag's refusals: --feather without
#      --guest is refused in plain words (a feather is a
#      guest with its card), and nothing is left behind.
#
# Prints PASS or FAIL.

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if ! ./niflac --bare --guest bare-examples/nifla-guest.nifla -o "$WORK/guest.bin" > "$WORK/plain.txt" 2>&1; then
    echo "FAIL: the plain guest build failed:"
    cat "$WORK/plain.txt"
    exit 1
fi
if ! ./niflac --bare --guest --feather bare-examples/nifla-guest.nifla -o "$WORK/guest.feather" > "$WORK/feather.txt" 2>&1; then
    echo "FAIL: the feather build failed:"
    cat "$WORK/feather.txt"
    exit 1
fi
echo "Built the feather:"
cat "$WORK/feather.txt"

python3 - "$WORK" <<'PYEOF'
import sys

work = sys.argv[1]
data = open(work + "/guest.feather", "rb").read()
plain = open(work + "/guest.bin", "rb").read()

head, sep, program = data.partition(b"\n\n")
if not sep:
    print("FAIL: the feather has no blank line between its card and its program")
    sys.exit(1)
lines = head.decode("utf-8").split("\n")
if lines[0] != "CARDNULL FEATHER 1":
    print("FAIL: the card's first line is %r, not 'CARDNULL FEATHER 1'" % lines[0])
    sys.exit(1)
fields = {}
for line in lines[1:]:
    key, _, value = line.partition(": ")
    fields[key] = value
if fields.get("name") != "nifla-guest":
    print("FAIL: the card's name is %r, not the program's own name 'nifla-guest'" % fields.get("name"))
    sys.exit(1)
if "guest door" not in fields.get("needs", ""):
    print("FAIL: the card's needs line does not name the guest door: %r" % fields.get("needs"))
    sys.exit(1)
if int(fields.get("bytes", "-1")) != len(program):
    print("FAIL: the card says %s bytes, but the program part is %d" % (fields.get("bytes"), len(program)))
    sys.exit(1)
h = 0xCBF29CE484222325
for b in program:
    h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
if fields.get("checksum") != "%016x" % h:
    print("FAIL: the card's checksum is %s, but the reckoning over the program is %016x" % (fields.get("checksum"), h))
    sys.exit(1)
if program != plain:
    print("FAIL: the feather's program part differs from the plain guest build")
    sys.exit(1)
print("The card is true: name, needs, %d bytes, checksum %016x — and the program is the plain guest build, byte for byte." % (len(program), h))
PYEOF
[ $? -eq 0 ] || exit 1

if ./niflac --feather bare-examples/nifla-guest.nifla -o "$WORK/nope.feather" > "$WORK/refusal.txt" 2>&1; then
    echo "FAIL: --feather without --guest was allowed"
    exit 1
fi
if ! grep -q "A feather is a guest program together with its card" "$WORK/refusal.txt"; then
    echo "FAIL: the --feather refusal said the wrong words:"
    cat "$WORK/refusal.txt"
    exit 1
fi
if [ -e "$WORK/nope.feather" ]; then
    echo "FAIL: the refused feather build left a file behind"
    exit 1
fi
echo "Refused, as expected (--feather without --guest): $(cat "$WORK/refusal.txt")"

echo "PASS feather (Stone 20: niflac lays a true card on a guest — a real .feather)"
