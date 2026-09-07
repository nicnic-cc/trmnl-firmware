#!/usr/bin/env bash
# Sync this fork with usetrmnl/trmnl-firmware.
#
# Layout this script assumes:
#   main        pristine mirror of upstream/main -- never carries local commits
#   firebeetle  the overlay: DFRobot FireBeetle 2 ESP32-E + Waveshare 4.26" 800x480
#
# The overlay is deliberately tiny (one device_list[] row in src/display.cpp, one
# platformio.ini env, this script) so that rebasing it onto a moved upstream is cheap.
# If a rebase conflicts it will almost always be the device_list[] row in
# src/display.cpp, because upstream added a neighbouring board -- keep both sides.
#
# Usage:
#   scripts/sync-upstream.sh            # fetch, fast-forward main, rebase overlay, push
#   scripts/sync-upstream.sh --dry-run  # show what would happen, change nothing

set -euo pipefail

cd "$(dirname "$0")/.."

MIRROR_BRANCH="main"
OVERLAY_BRANCH="${OVERLAY_BRANCH:-firebeetle}"
UPSTREAM_URL="https://github.com/usetrmnl/trmnl-firmware.git"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  would run: $*"
  else
    echo "  \$ $*"
    "$@"
  fi
}

if ! git remote get-url upstream > /dev/null 2>&1; then
  echo "Adding 'upstream' remote -> $UPSTREAM_URL"
  run git remote add upstream "$UPSTREAM_URL"
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is dirty. Commit or stash first."
  exit 1
fi

START_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "==> Fetching upstream"
run git fetch upstream --tags

echo "==> Fast-forwarding $MIRROR_BRANCH to upstream/main"
run git checkout "$MIRROR_BRANCH"
# --ff-only is the guard: it fails loudly if main ever picked up a local commit.
run git merge --ff-only upstream/main
# Deliberately no --tags: upstream's release tags are fetched locally but not
# republished to the fork, which would just be noise.
run git push origin "$MIRROR_BRANCH"

echo "==> Rebasing $OVERLAY_BRANCH onto upstream/main"
run git checkout "$OVERLAY_BRANCH"
if [ "$DRY_RUN" = "0" ]; then
  if ! git rebase upstream/main; then
    echo
    echo "Rebase stopped on a conflict. Resolve it, then:"
    echo "  git rebase --continue && git push --force-with-lease origin $OVERLAY_BRANCH"
    echo "Or bail out with: git rebase --abort"
    exit 1
  fi
else
  echo "  would run: git rebase upstream/main"
fi

echo "==> Pushing $OVERLAY_BRANCH"
run git push --force-with-lease origin "$OVERLAY_BRANCH"

echo "==> Overlay vs upstream:"
if [ "$DRY_RUN" = "0" ]; then
  git diff --stat upstream/main "$OVERLAY_BRANCH"
fi

run git checkout "$START_BRANCH"

echo
echo "Done. Rebuild with:"
echo "  pio run -e dfrobot_firebeetle2_esp32e"
