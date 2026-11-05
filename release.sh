#!/usr/bin/env bash
# ------------------------------------------------------------
#  release.sh – cuts a release of LF Hub from dev
#
#  Bumps <Version> in lfhub.csproj to M.N+1.0 (minor) or M+1.0.0 (major) on a
#  release/vX.Y.0 branch cut from dev, pushes it and opens two PRs: release → main
#  (merging it builds the `latest` image and tags vX.Y.0) and release → dev (so the
#  dev bumps continue from the release). Merge both with a merge commit.
# ------------------------------------------------------------
set -euo pipefail
trap 'echo "Error, aborting"; exit 1' ERR

VERSION_FILE="lfhub.csproj"
DEV_BRANCH="dev"
MAIN_BRANCH="main"

pause()    { read -rp "Press Enter to continue (Ctrl-C to abort)… "; }
echo_run() { echo "+ $*"; "$@"; }

echo_run git fetch origin "$DEV_BRANCH"
if ! diff -q <(git show "origin/${DEV_BRANCH}:release.sh") "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
  echo "This release.sh differs from origin/${DEV_BRANCH}:release.sh. Switch to the latest ${DEV_BRANCH} and run it again."
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "The working tree has changes. Commit or stash them first."
  exit 1
fi

echo_run git switch "$DEV_BRANCH"
echo_run git pull --ff-only

old_ver=$(sed -nE 's|^ *<Version>([0-9]+\.[0-9]+\.[0-9]+)</Version>.*|\1|p' "$VERSION_FILE")
if [ -z "$old_ver" ]; then
  echo "No <Version>MAJOR.MINOR.PATCH</Version> in $VERSION_FILE."
  exit 1
fi
major_candidate="$(awk -F. '{printf "%d.0.0", $1 + 1}' <<<"$old_ver")"
minor_candidate="$(awk -F. '{printf "%d.%d.0", $1, $2 + 1}' <<<"$old_ver")"

echo
echo "dev is at $old_ver. Which release?"
echo "  1) Major → $major_candidate"
echo "  2) Minor → $minor_candidate"
read -rp "Enter 1 or 2 (default 2): " choice
case "$choice" in
  1) new_ver="$major_candidate" ;;
  ""|2) new_ver="$minor_candidate" ;;
  *) echo "Invalid choice."; exit 1 ;;
esac

RELEASE_BRANCH="release/v${new_ver}"
echo_run git switch -c "$RELEASE_BRANCH"
perl -i -pe "s|<Version>\Q${old_ver}\E</Version>|<Version>${new_ver}</Version>|" "$VERSION_FILE"
echo_run git diff "$VERSION_FILE"; pause
# No [skip ci]: main's push builds the `latest` image and tags the release; dev's
# workflow sees the version set in the push and does not bump it again.
echo_run git commit -m "Update version to ${new_ver}" "$VERSION_FILE"

echo "Build and test the release branch now (dotnet build, dotnet test)."; pause

read -rp "Push ${RELEASE_BRANCH} and open the PRs? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
  echo "Not pushed. When ready: git push origin ${RELEASE_BRANCH}"
  exit 0
fi

echo_run git push origin "$RELEASE_BRANCH"
REPO_SLUG="$(git remote get-url origin | sed -E -e 's#\.git$##' -e 's#^.*github\.com[:/]##')"

gh pr create --repo "$REPO_SLUG" --base "$DEV_BRANCH" --head "$RELEASE_BRANCH" \
  --title "Sync v${new_ver} version to dev" \
  --body "Brings the v${new_ver} version back to dev so the dev bumps continue from it. Merge with a merge commit."

gh pr create --repo "$REPO_SLUG" --base "$MAIN_BRANCH" --head "$RELEASE_BRANCH" \
  --title "Release v${new_ver}" \
  --body "Release v${new_ver}. Merging builds the latest image and tags v${new_ver}. Merge with a merge commit."

echo "Merge both PRs, then create a GitHub release for v${new_ver} once the tag exists."
