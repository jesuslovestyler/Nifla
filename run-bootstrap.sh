#!/bin/sh
# Stone 61 proof: the bootstrap — the compiler
# compiles itself, and the self-built compiler
# reproduces itself byte for byte.
#
# The chain this script drives, in a scratch folder:
#
#   1. The seed — the Swift toolchain in src/,
#      built by build.sh into ./niflac — compiles
#      selfhost/nifla-front.nifla. The build keeps
#      the generated Swift beside the binary, as
#      compileMain keeps it: that text is S0, and
#      the binary is the first-generation front
#      end, F1.
#   2. F1, in its compile mode, compiles its own
#      source: the printed Swift is S1. S1 must
#      equal S0 byte for byte — the Nifla-written
#      translator and the Swift translator are one
#      translator, on the largest program in the
#      corpus: the front end itself. (The corpus
#      gates compare the two sides' printing of
#      this file on every run; here the equality
#      is load-bearing, so it is asserted on the
#      kept file itself.)
#   3. S1 is built into the second-generation
#      front end, F2 — handed to swiftc under the
#      name main.swift beside the runtime, exactly
#      as compileMain's driver hands it over. The
#      driving here is the driver's work, standing
#      in shell where compileMain's driver half
#      stands in Swift: Stones 53–60 recorded those
#      halves — the scratch folder, the running of
#      swiftc and the assemblers, the 'Made' lines —
#      as driver machinery outside the identity
#      claims, and this stone does not move them.
#      What the stone claims is the translator's
#      fixed point, and it is F2 that proves it:
#   4. F2, in its compile mode, compiles the front
#      end's source again: the printed Swift is
#      S2. S2 must equal S1 byte for byte — the
#      compiler built from the compiler's own
#      output writes the same compiler again.
#   5. F2 is then exercised as a front end, not
#      only as a text: across the corpus fixtures
#      and the front end's own source, in the
#      check, compile, barecompile and
#      barecompile-arm modes, F2's stdout, stderr
#      and exit must equal F1's on every file —
#      the self-built generation behaves as the
#      seed-built generation behaves.
#
# With the fixed point proved, the ledger records
# the seed's retirement: src/ stands frozen as
# the honest first builder, kept for honesty;
# the living standard is the front end itself,
# which now builds the front end.

set -u
cd "$(dirname "$0")"

fail=0
note_fail() {
    echo "FAIL bootstrap: $1"
    fail=1
}

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

echo "Building the seed (build.sh)..."
if ! ./build.sh > "$SCRATCH/seed-build.log" 2>&1; then
    cat "$SCRATCH/seed-build.log"
    note_fail "the seed did not build"
    echo "FAIL bootstrap"
    exit 1
fi

FRONT=selfhost/nifla-front.nifla

echo "Seed compiles the front end (generation 1)..."
if ! ./niflac "$FRONT" -o "$SCRATCH/f1" > "$SCRATCH/seed-compile.log" 2>&1; then
    cat "$SCRATCH/seed-compile.log"
    note_fail "the seed did not compile the front end"
    echo "FAIL bootstrap"
    exit 1
fi
# compileMain keeps the generated Swift beside the output.
S0="$SCRATCH/f1.swift"
[ -f "$S0" ] || { note_fail "the seed kept no generated Swift"; echo "FAIL bootstrap"; exit 1; }

echo "Generation 1 compiles its own source..."
timeout 600 "$SCRATCH/f1" compile "$FRONT" > "$SCRATCH/s1.txt" 2> "$SCRATCH/s1.err"
ec=$?
[ "$ec" -eq 0 ] || note_fail "generation 1's self-compile exited $ec"
if ! cmp -s "$S0" "$SCRATCH/s1.txt"; then
    note_fail "generation 1's self-compile differs from the seed's kept Swift"
fi

echo "Building generation 2 from generation 1's own output..."
mkdir "$SCRATCH/build2"
cp "$SCRATCH/s1.txt" "$SCRATCH/build2/main.swift"
SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if command -v swiftc >/dev/null 2>&1; then
        SWIFTC="$(command -v swiftc)"
    elif [ -x /opt/swift/usr/bin/swiftc ]; then
        SWIFTC=/opt/swift/usr/bin/swiftc
    elif [ -x "$HOME/swift/usr/bin/swiftc" ]; then
        SWIFTC="$HOME/swift/usr/bin/swiftc"
    elif [ -x "$HOME/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc" ]; then
        SWIFTC="$HOME/workspace/turtle-browser/harness-038/toolchain/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swiftc"
    fi
fi
[ -n "$SWIFTC" ] || { note_fail "no swiftc found for the generation-2 build (build.sh's search found none either)"; echo "FAIL bootstrap"; exit 1; }
if ! timeout 1200 "$SWIFTC" "$SCRATCH/build2/main.swift" runtime/NiflaRuntime.swift -o "$SCRATCH/f2" > "$SCRATCH/f2-build.log" 2>&1; then
    cat "$SCRATCH/f2-build.log"
    note_fail "generation 2 did not build"
    echo "FAIL bootstrap"
    exit 1
fi

echo "Generation 2 compiles the front end's source..."
timeout 600 "$SCRATCH/f2" compile "$FRONT" > "$SCRATCH/s2.txt" 2> "$SCRATCH/s2.err"
ec=$?
[ "$ec" -eq 0 ] || note_fail "generation 2's self-compile exited $ec"
if ! cmp -s "$SCRATCH/s1.txt" "$SCRATCH/s2.txt"; then
    note_fail "the fixed point failed: generation 2's self-compile differs from generation 1's"
fi

echo "Generation 2 against generation 1 across the fixtures..."
checked=0
for mode in check compile barecompile barecompile-arm; do
    for f in front-examples/*.nifla compile-examples/*.nifla barecompile-examples/*.nifla barecompile-arm-examples/*.nifla; do
        [ -f "$f" ] || continue
        timeout 120 "$SCRATCH/f1" "$mode" "$f" > "$SCRATCH/g1.out" 2> "$SCRATCH/g1.err"; e1=$?
        timeout 120 "$SCRATCH/f2" "$mode" "$f" > "$SCRATCH/g2.out" 2> "$SCRATCH/g2.err"; e2=$?
        checked=$((checked + 1))
        if [ "$e1" -ne "$e2" ] || ! cmp -s "$SCRATCH/g1.out" "$SCRATCH/g2.out" || ! cmp -s "$SCRATCH/g1.err" "$SCRATCH/g2.err"; then
            note_fail "generations differ on $f in mode $mode (exits $e1/$e2)"
        fi
    done
done
echo "generations compared on $checked fixture runs"

echo "Generation 2 against generation 1 on the front end's own source, every mode..."
for mode in tokens tree check compile barevalid barecompile barecompile-arm; do
    timeout 900 "$SCRATCH/f1" "$mode" "$FRONT" > "$SCRATCH/g1.out" 2> "$SCRATCH/g1.err"; e1=$?
    timeout 900 "$SCRATCH/f2" "$mode" "$FRONT" > "$SCRATCH/g2.out" 2> "$SCRATCH/g2.err"; e2=$?
    if [ "$e1" -ne "$e2" ] || ! cmp -s "$SCRATCH/g1.out" "$SCRATCH/g2.out" || ! cmp -s "$SCRATCH/g1.err" "$SCRATCH/g2.err"; then
        note_fail "generations differ on the front end's own source in mode $mode (exits $e1/$e2)"
    fi
    echo "  mode $mode compared (exits $e1/$e2)"
done

if [ "$fail" -eq 0 ]; then
    echo "PASS bootstrap (Stone 61: the seed's kept Swift, generation 1's self-compile and generation 2's self-compile are one text byte for byte, and the self-built generation answers as the seed-built generation answers across $checked fixture runs and the front end's own source in every mode)"
else
    echo "FAIL bootstrap"
    exit 1
fi
