#!/usr/bin/env bash
# Run both agent-shell-workspace suites.
#
# Phase 1 is the unit suite under --batch: pure logic with no window
# management, so batch is safe, fast, and fails first.
#
# Phase 2 is the e2e suite in a REAL Emacs, not --batch.  Batch Emacs
# never runs redisplay and never restores a window configuration, so
# window-point bugs -- the ones that suite exists to catch -- simply do
# not reproduce there.  `script' allocates a pty so a -nw Emacs gets a
# genuine terminal frame with genuine redisplay.
#
# Usage: test/run.sh [path-to-emacs]
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emacs="${1:-emacs}"

echo "== unit suite (emacs --batch) =="
"$emacs" --batch -Q -L "$here/.." -L "$here" \
  -l agent-shell-workspace-unit-test \
  -f ert-run-tests-batch-and-exit 2>&1
unit_status=$?

echo
echo "== e2e suite (real frame) =="
out="$(mktemp -t agent-shell-workspace-test.XXXXXX)"
export AGENT_SHELL_WORKSPACE_TEST_OUT="$out"

# Force a cursor-addressable terminal. Emacs refuses to start a -nw frame
# under TERM=dumb, which is what CI and non-interactive shells often set,
# and ${TERM:-...} would not override a set-but-useless value.
case "${TERM:-}" in
  ""|dumb|unknown) export TERM=xterm-256color ;;
esac

# -Q so a user's own config cannot change window or tab behaviour under
# the tests.
script -qec \
  "$emacs -nw -Q --eval '(setq inhibit-startup-screen t)' \
     -l '$here/run.el' -f agent-shell-workspace-run-tests" \
  /dev/null >/dev/null 2>&1
e2e_status=$?

if [ -s "$out" ]; then
  cat "$out"
else
  echo "no test output produced (emacs exited $e2e_status)"
fi
rm -f "$out"

[ "$unit_status" -eq 0 ] && [ "$e2e_status" -eq 0 ]
