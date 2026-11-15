#!/bin/sh
# Stone 21 proof: the feather checker.
#
# `feathercheck` (built by ./build.sh, the third name of the one
# program) reads a .feather and answers in plain words whether
# its card is true. This proof checks the three roads:
#
#   1. a true feather (built with niflac --feather): the card is
#      declared true, with the name, the needs, and the stated
#      and reckoned checksums agreeing — exit 0.
#   2. the same feather with one byte flipped in its program:
#      the card is declared not true, in plain words — exit 1.
#   3. the same feather with its card damaged (a checksum
#      letter struck out): the file is refused as not a whole
#      feather, in plain words — exit 1.
#
# Prints PASS or FAIL.

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }
[ -x ./feathercheck ] || { echo "FAIL: feathercheck was not built"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

./niflac --bare --guest --feather bare-examples/nifla-guest.nifla -o "$WORK/guest.feather" >/dev/null || { echo "FAIL: the feather did not build"; exit 1; }

echo "--- 1. a true feather ---"
OUT=$(./feathercheck "$WORK/guest.feather") || { echo "FAIL: a true feather was refused:"; echo "$OUT"; exit 1; }
echo "$OUT"
echo "$OUT" | grep -q "^Feather: nifla-guest$" || { echo "FAIL: the name line is wrong"; exit 1; }
echo "$OUT" | grep -q "^Needs: the guest door (desk version 1)$" || { echo "FAIL: the needs line is wrong"; exit 1; }
echo "$OUT" | grep -q "^The card is true: " || { echo "FAIL: the verdict line is missing"; exit 1; }
SAYS=$(echo "$OUT" | sed -n 's/^The card says the program is [0-9]* bytes, with checksum \([0-9a-f]*\)\.$/\1/p')
STANDS=$(echo "$OUT" | sed -n 's/^The program as it stands is [0-9]* bytes, with checksum \([0-9a-f]*\)\.$/\1/p')
[ -n "$SAYS" ] && [ "$SAYS" = "$STANDS" ] || { echo "FAIL: stated and reckoned checksums disagree on a true feather"; exit 1; }

python3 - "$WORK" <<'PYEOF'
import sys
work = sys.argv[1]
data = bytearray(open(work + "/guest.feather", "rb").read())
start = data.index(b"\n\n") + 2
flipped = bytearray(data)
flipped[start + 100] ^= 0xFF
open(work + "/guest-flipped.feather", "wb").write(flipped)
# A damaged card: strike one letter out of the checksum line.
text = data.decode("latin1")
i = text.index("checksum: ") + len("checksum: ")
damaged = text[:i] + text[i + 1:]
open(work + "/guest-damaged.feather", "wb").write(damaged.encode("latin1"))
PYEOF

echo "--- 2. one byte flipped in the program ---"
if OUT=$(./feathercheck "$WORK/guest-flipped.feather"); then
    echo "FAIL: a flipped feather was declared true"
    exit 1
fi
echo "$OUT"
echo "$OUT" | grep -q "^The card is not true: " || { echo "FAIL: the not-true verdict line is missing"; exit 1; }

echo "--- 3. a damaged card ---"
if OUT=$(./feathercheck "$WORK/guest-damaged.feather"); then
    echo "FAIL: a damaged card was declared true"
    exit 1
fi
echo "$OUT"
echo "$OUT" | grep -q "^This is not a whole feather: " || { echo "FAIL: the damaged-card refusal is missing"; exit 1; }

echo "PASS feathercheck (Stone 21: the doorman's test — true, flipped, and damaged feathers answered in plain words)"
