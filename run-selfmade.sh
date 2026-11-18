#!/bin/sh
# Stone 25 proof: the first self-made tool.
#
# tools/feathercheck.nifla is the Stone 21 feather checker
# rewritten in Nifla itself. This proof builds it with
# niflac into a standalone program, then runs it and the
# hosted feathercheck across the whole feather corpus —
# a true feather, one with a byte flipped in its program,
# one with a damaged card, the two rendering edges from
# Stone 25's ledger as cards of their own (a name written
# in UTF-8 letters; a name holding bytes that are not
# letters; a stated count past the language's exact
# reach; a stated count past the machine whole number's
# reach; a stated count with leading zeros), the OS's
# own welcome feather, a missing file, and a wrongly-made
# call — and requires their answers to be identical:
# every line of standard output (and of the usage line
# on standard error), and every exit code.
#
# Prints PASS or FAIL.

set -u
cd "$(dirname "$0")"
fail() { echo "FAIL selfmade: $1"; exit 1; }

./build.sh >/dev/null || fail "build.sh failed"
[ -x ./niflac ] || fail "niflac was not built"
[ -x ./feathercheck ] || fail "feathercheck was not built"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The corpus.
./niflac --bare --guest --feather bare-examples/nifla-guest.nifla -o "$WORK/guest.feather" >/dev/null \
    || fail "the corpus feather did not build"
python3 - "$WORK" <<'PYEOF' || fail "the corpus variants were not made"
import sys
work = sys.argv[1]
data = bytearray(open(work + "/guest.feather", "rb").read())
start = data.index(b"\n\n") + 2
flipped = bytearray(data)
flipped[start + 100] ^= 0xFF
open(work + "/guest-flipped.feather", "wb").write(flipped)
text = data.decode("latin1")
i = text.index("checksum: ") + len("checksum: ")
damaged = text[:i] + text[i + 1:]
open(work + "/guest-damaged.feather", "wb").write(damaged.encode("latin1"))
# Stone 29: the two rendering edges from Stone 25's
# ledger, as cards. The name line's bytes are swapped
# (the checksum covers the program, not the card's
# words), and the 'bytes:' line is restated.
parts = bytes(data).split(b"\n", 2)
head, rest = parts[0] + b"\n", parts[2]
open(work + "/guest-utf8.feather", "wb").write(head + "name: nifla-güest".encode("utf-8") + b"\n" + rest)
open(work + "/guest-unclean.feather", "wb").write(head + b"name: nifla-g\xff\xc3est" + b"\n" + rest)
def restated(n):
    out = bytearray(data)
    i = out.index(b"bytes: ") + len(b"bytes: ")
    j = out.index(b"\n", i)
    return bytes(out[:i]) + n + bytes(out[j:])
open(work + "/guest-bigcount.feather", "wb").write(restated(b"9007199254740993"))
open(work + "/guest-hugecount.feather", "wb").write(restated(b"9223372036854775808"))
open(work + "/guest-zerocount.feather", "wb").write(restated(b"007"))
PYEOF
CASES="guest.feather guest-flipped.feather guest-damaged.feather guest-utf8.feather guest-unclean.feather guest-bigcount.feather guest-hugecount.feather guest-zerocount.feather not-there.feather"
if [ -f ../cardnull-os-2/src/welcome-feather.nifla ]; then
    ./niflac --bare --guest --feather ../cardnull-os-2/src/welcome-feather.nifla -o "$WORK/welcome.feather" >/dev/null \
        || fail "the OS welcome feather did not build"
    CASES="$CASES welcome.feather"
else
    echo "note: ../cardnull-os-2 was not found, so the OS welcome feather is not in this run's corpus"
fi

# The self-made tool, built by the repo's normal flow.
./niflac tools/feathercheck.nifla -o "$WORK/feathercheck-nifla" >/dev/null \
    || fail "the Nifla feather checker did not compile"

compare() {
    # $1 = label; the rest is the file argument (or none)
    label="$1"; shift
    ./feathercheck "$@" >"$WORK/hosted.out" 2>"$WORK/hosted.err"; hosted_code=$?
    "$WORK/feathercheck-nifla" "$@" >"$WORK/nifla.out" 2>"$WORK/nifla.err"; nifla_code=$?
    [ "$hosted_code" = "$nifla_code" ] \
        || fail "$label: exit codes differ (hosted $hosted_code, Nifla $nifla_code)"
    cmp -s "$WORK/hosted.out" "$WORK/nifla.out" || fail "$label: the answers differ:
--- hosted ---
$(cat "$WORK/hosted.out")
--- Nifla ---
$(cat "$WORK/nifla.out")"
    cmp -s "$WORK/hosted.err" "$WORK/nifla.err" || fail "$label: the error channels differ"
    echo "agree: $label (exit $hosted_code)"
}

for f in $CASES; do
    compare "$f" "$WORK/$f"
done
compare "called with no file"

echo "PASS selfmade (Stone 25: the feather checker written in Nifla agrees with the hosted checker on every line and every exit code, across the whole corpus)"
