#!/usr/bin/env bash
# Runs every automated gameplay test headless. Usage: tests/run_tests.sh /path/to/godot
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
# Refresh the class cache and imports first (needed after new scripts are added).
"$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
for t in tests/test_*.gd; do
  [ "$(basename "$t")" = "test_base.gd" ] && continue
  echo "=== $t"
  "$GODOT" --headless --path . --script "res://$t" 2>&1 | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR|Parse Error"
  [ "${PIPESTATUS[0]}" -ne 0 ] && status=1
done
exit $status
