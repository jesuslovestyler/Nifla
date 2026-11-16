#!/bin/sh
# The Browser Stone's proof: the hosted conformance corpus,
# run through the JavaScript interpreter.
#
# web/nifla.js is a Nifla interpreter written in JavaScript,
# so Nifla programs can run inside a web page. This script
# proves it against the expectations the Swift suites already
# record — nothing here invents its own expectations:
#
#   - the interpreted suite (examples/*.nifla with their
#     .expected / .error files, as in run_tests.sh),
#   - every hosted example in PRIMER.md (as in run-primer.sh),
#   - every hosted example in TUTORIAL.md (as in
#     run-tutorial.sh).
#
# Floor examples run on the interpreter's simulated floor
# desk and are compared like the hosted examples (the desk's
# own proof is run-web-floor.sh); bare-metal examples are
# compile-only on every door and are noted, not run.
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
    echo "FAIL: Node is not available on this bench, and the web proof needs it."
    echo "The interpreter (web/nifla.js) itself runs in any browser; only this"
    echo "proof runner needs Node."
    exit 1
fi

"$NODE" web/run-corpus.js
