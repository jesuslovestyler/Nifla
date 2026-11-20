#!/bin/sh
# Stone 49: the front end's single gate.
#
# Runs the whole identity proof for the all-Nifla port's
# first leg in order — the lexer proof (Stone 47), the
# parser proof (Stone 48), and the generated sweep
# (Stone 49) — stopping at the first failure. This is the
# one command future work runs to prove the front end
# whole: selfhost/nifla-front.nifla against the untouched
# Swift front end, token for token and tree for tree.

set -u
cd "$(dirname "$0")"

./run-front-lexer.sh || { echo "FAIL front: the lexer proof failed — the gate stops here"; exit 1; }
./run-front-parser.sh || { echo "FAIL front: the parser proof failed — the gate stops here"; exit 1; }
./run-front-sweep.sh || { echo "FAIL front: the generated sweep failed — the gate stops here"; exit 1; }

echo "PASS front (Stone 49: the Nifla-written front end is byte-identical to the Swift front end — lexer and parser — across the whole corpus and the 102 fixtures in both modes, and across the generated sweep of 300 numbers, 200 programs and 200 token soup, boundary 3 noted)"
