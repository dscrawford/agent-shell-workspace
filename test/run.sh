#!/usr/bin/env bash
# Run the agent-shell-workspace suite in a REAL Emacs, not --batch.
#
# Batch Emacs never runs redisplay and never restores a window
# configuration, so window-point bugs -- the ones this suite exists to
# catch -- simply do not reproduce there. `script' allocates a pty so a
# -nw Emacs gets a genuine terminal frame with genuine redisplay.
#
# Usage: test/run.sh [path-to-emacs]
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emacs="${1:-emacs}"
out="$(mktemp -t agent-shell-workspace-test.XXXXXX)"

export AGENT_SHELL_WORKSPACE_TEST_OUT="$out"

# Force a cursor-addressable terminal. Emacs refuses to start a -nw frame
# under TERM=dumb, which is what CI and non-interactive shells often set,
# and ${TERM:-...} would not override a set-but-useless value.
case "${TERM:-}" in
  ""|dumb|unknown) export TERM=xterm-256color ;;
esac

# -Q so a user's own config cannot change window or tab behaviour under
# the tests. LINES/COLUMNS give the frame room for a sidebar plus a main
# window; the default 80x24 from script is too cramped to split reliably.
script -qec \
  "$emacs -nw -Q --eval '(setq inhibit-startup-screen t)' \
     -l '$here/run.el' -f agent-shell-workspace-run-tests" \
  /dev/null >/dev/null 2>&1
status=$?

if [ -s "$out" ]; then
  cat "$out"
else
  echo "no test output produced (emacs exited $status)"
fi
rm -f "$out"
exit $status
