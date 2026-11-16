#!/bin/sh
# The floor desk's proof: the floor corpus, run through the
# JavaScript interpreter's simulated desk.
#
# web/nifla.js runs floor blocks on a desk — a simulation of
# the floor contract (the desk registers and the one block
# of bytes) that carries out the block's assembly instruction
# by instruction. This script proves the desk against the
# expectations the Swift suites already record:
#
#   - the floor suite (floor-examples/*.nifla with their
#     .expected files, as in run-floor.sh),
#   - the checker's floor refusals (checker-examples, as in
#     run-checker.sh),
#   - every ```nifla-floor example in PRIMER.md and
#     TUTORIAL.md, against its ```expected block.
#
# It also proves the desk's honesty: a block using an
# instruction the desk does not cover is refused before
# anything in the program runs, and a block reaching past
# the desk — memory outside it, a division by zero, a call
# it does not answer, a loop that never ends — is stopped
# in plain words naming the limit.
#
# Needs Node (any current version) — the interpreter itself
# has no dependencies and runs the same in a browser.

set -u
cd "$(dirname "$0")"

NODE=""
if command -v node >/dev/null 2>&1; then
    NODE="node"
elif [ -x "$HOME/workspace/node/bin/node" ]; then
    NODE="$HOME/workspace/node/bin/node"
else
    echo "FAIL: Node is not available on this bench, and the web floor proof needs it."
    echo "The interpreter (web/nifla.js) itself runs in any browser; only this"
    echo "proof runner needs Node."
    exit 1
fi

"$NODE" web/run-floor-corpus.js
