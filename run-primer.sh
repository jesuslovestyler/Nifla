#!/bin/sh
# Stone 22 proof: the Primer's examples are true.
#
# PRIMER.md — the language's book — carries a small runnable
# example for every grammar word and every toolbox word.
# This proof extracts every example and runs it against the
# language as it stands, so the book can never drift from
# the language it teaches:
#
#   ```nifla            a hosted program: run by the
#                       interpreter AND by a niflac-compiled
#                       program; both must print exactly the
#                       ```expected block that follows it.
#   ```nifla exit=N     the same, for a program that ends
#                       with exitwith(N).
#   ```nifla-floor      a program holding a floor block: the
#                       interpreter refuses those by design,
#                       so it is compiled and run, and its
#                       output compared the same way.
#   ```nifla-bare       a bare-metal program: compiled with
#                       niflac --bare (checker and bare
#                       validator and code generator all
#                       exercise it); it runs on bare metal,
#                       where the bare suites boot its kind.
#   ```nifla-bare-guest the same, for a guest program:
#                       compiled with --bare --guest.
#
# Every example runs with the same two program arguments,
# Ada and Byron, which the arguments() example relies on.
#
# Prints PASS or FAIL.

set -u
cd "$(dirname "$0")"

./build.sh >/dev/null || { echo "FAIL: build.sh failed"; exit 1; }

python3 - <<'PYEOF'
import re
import subprocess
import sys
import tempfile
import os

NIFLA = os.path.abspath("./nifla")
NIFLAC = os.path.abspath("./niflac")

text = open("PRIMER.md", encoding="utf-8").read()
blocks = []
pos = 0
while True:
    start = text.find("```", pos)
    if start < 0:
        break
    end_of_line = text.find("\n", start)
    info = text[start + 3:end_of_line].strip()
    close = text.find("```", end_of_line)
    if close < 0:
        print("FAIL: an unclosed fenced block in PRIMER.md")
        sys.exit(1)
    body = text[end_of_line + 1:close]
    blocks.append((info, body))
    pos = close + 3

work = tempfile.mkdtemp()
failures = 0
ran = 0
compiled_only = 0
i = 0

def check(label, got_out, want_out, got_code, want_code):
    global failures
    if got_out != want_out:
        failures += 1
        print(f"FAIL: {label}: output differs")
        print(f"  expected: {want_out!r}")
        print(f"  got:      {got_out!r}")
    if got_code != want_code:
        failures += 1
        print(f"FAIL: {label}: exit code {got_code}, expected {want_code}")

while i < len(blocks):
    info, body = blocks[i]
    if info == "expected":
        print("FAIL: an ```expected block with no example before it")
        failures += 1
        i += 1
        continue
    if not (info == "nifla" or info.startswith("nifla ") or info in ("nifla-floor", "nifla-bare", "nifla-bare-guest")):
        i += 1
        continue
    label = f"example {ran + compiled_only + 1} ({info})"
    src = os.path.join(work, f"ex{ran + compiled_only + 1}.nifla")
    with open(src, "w", encoding="utf-8") as f:
        f.write(body)
    if info in ("nifla-bare", "nifla-bare-guest"):
        cmd = [NIFLAC, "--bare"] + (["--guest"] if info == "nifla-bare-guest" else []) + [src, "-o", src + ".bin"]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            failures += 1
            print(f"FAIL: {label}: the bare build refused it:\n{r.stderr}")
        compiled_only += 1
        i += 1
        continue
    if i + 1 >= len(blocks) or blocks[i + 1][0] != "expected":
        print(f"FAIL: {label} is not followed by an ```expected block")
        failures += 1
        i += 1
        continue
    want = blocks[i + 1][1]
    if want.endswith("\n"):
        want = want[:-1]
    want_out = want + "\n" if want else ""
    want_code = 0
    m = re.search(r"exit=(\d+)", info)
    if m:
        want_code = int(m.group(1))
    if info != "nifla-floor":
        r = subprocess.run([NIFLA, src, "Ada", "Byron"],
                           capture_output=True, text=True, timeout=30, cwd=work)
        check(label + " [interpreted]", r.stdout, want_out, r.returncode, want_code)
    exe = src + ".exe"
    r = subprocess.run([NIFLAC, src, "-o", exe],
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        failures += 1
        print(f"FAIL: {label}: niflac refused it:\n{r.stderr}")
    else:
        r = subprocess.run([exe, "Ada", "Byron"],
                           capture_output=True, text=True, timeout=30, cwd=work)
        check(label + " [compiled]", r.stdout, want_out, r.returncode, want_code)
    ran += 1
    i += 2

print(f"Primer examples: {ran} executed, {compiled_only} bare-compiled, {failures} failure(s)")
if failures:
    sys.exit(1)
if ran < 30:
    print("FAIL: suspiciously few runnable examples — the book is thinner than the language")
    sys.exit(1)
print("PASS primer (Stone 22: every example in PRIMER.md runs true, interpreted and compiled)")
PYEOF
