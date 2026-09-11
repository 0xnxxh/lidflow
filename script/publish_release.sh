#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/version.sh"

TAG="v$APP_VERSION"
REPO="0xnxxh/lidflow"
DMG_PATH="$ROOT_DIR/dist/LidFlow-v$APP_VERSION.dmg"
APPCAST_PATH="$ROOT_DIR/dist/appcast.xml"
RELEASE_NOTES_PATH="$ROOT_DIR/RELEASE_NOTES.md"
GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --absolute-git-dir)"
LOCK_DIR="$GIT_DIR/lidflow-release.lock"

fail() {
  echo "$1" >&2
  exit 1
}

release_lock_acquired=0
release_cleanup() {
  if [[ "$release_lock_acquired" == "1" ]]; then
    rmdir "$LOCK_DIR"
  fi
}
trap release_cleanup EXIT

if [[ "${CONFIRM_PUBLISH:-}" != "1" ]]; then
  echo "refusing to publish without CONFIRM_PUBLISH=1" >&2
  exit 2
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "another release is already running; lock exists: $LOCK_DIR"
fi
release_lock_acquired=1

if [[ ! -s "$RELEASE_NOTES_PATH" ]]; then
  fail "missing release notes: $RELEASE_NOTES_PATH"
fi

if ! head -n 1 "$RELEASE_NOTES_PATH" | grep -qx "# LidFlow $TAG"; then
  fail "release notes must start with: # LidFlow $TAG"
fi

if [[ "$(git -C "$ROOT_DIR" status --short)" != "" ]]; then
  fail "working tree is not clean; commit before publishing"
fi

release_lookup=""
if release_lookup="$(gh release view "$TAG" --repo "$REPO" --json tagName --jq .tagName 2>&1)"; then
  fail "release already exists: $TAG"
fi
if [[ "$release_lookup" != *"release not found"* ]]; then
  fail "could not verify that $TAG is unpublished: ${release_lookup:-unknown gh error}"
fi

branch="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD || true)"
if [[ "$branch" != "main" ]]; then
  fail "release must run from main; current branch: ${branch:-detached HEAD}"
fi

head_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
remote_main="$(git -C "$ROOT_DIR" ls-remote origin refs/heads/main | awk '{print $1}')"
if [[ -z "$remote_main" ]]; then
  fail "origin/main was not found"
fi
if [[ "$head_commit" != "$remote_main" ]]; then
  fail "main is not synchronized with origin/main; push or pull before publishing"
fi

echo "release check: $TAG"
"$ROOT_DIR/script/release_check.sh"

if [[ "$(git -C "$ROOT_DIR" status --short)" != "" ]]; then
  fail "working tree changed during release check"
fi

local_tag_commit="$(git -C "$ROOT_DIR" rev-parse --verify "$TAG^{commit}" 2>/dev/null || true)"
if [[ -n "$local_tag_commit" && "$local_tag_commit" != "$head_commit" ]]; then
  fail "local tag $TAG points to $local_tag_commit, expected $head_commit"
fi

remote_tag_object="$(git -C "$ROOT_DIR" ls-remote origin "refs/tags/$TAG" | awk '{print $1}')"
if [[ -n "$remote_tag_object" && -z "$local_tag_commit" ]]; then
  git -C "$ROOT_DIR" fetch origin "refs/tags/$TAG:refs/tags/$TAG"
  local_tag_commit="$(git -C "$ROOT_DIR" rev-parse --verify "$TAG^{commit}")"
fi
if [[ -n "$local_tag_commit" && "$local_tag_commit" != "$head_commit" ]]; then
  fail "tag $TAG points to $local_tag_commit, expected $head_commit"
fi

if [[ -z "$local_tag_commit" ]]; then
  git -C "$ROOT_DIR" tag -a "$TAG" -m "LidFlow $APP_VERSION"
fi

git -C "$ROOT_DIR" push origin "refs/tags/$TAG"
local_tag_object="$(git -C "$ROOT_DIR" rev-parse --verify "$TAG")"
remote_tag_object="$(git -C "$ROOT_DIR" ls-remote origin "refs/tags/$TAG" | awk '{print $1}')"
if [[ "$local_tag_object" != "$remote_tag_object" ]]; then
  fail "remote tag $TAG does not match the local tag"
fi

local_dmg_sha="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
local_appcast_sha="$(shasum -a 256 "$APPCAST_PATH" | awk '{print $1}')"

gh release create "$TAG" \
  "$DMG_PATH" \
  "$APPCAST_PATH" \
  --repo "$REPO" \
  --title "LidFlow $APP_VERSION" \
  --notes-file "$RELEASE_NOTES_PATH" \
  --verify-tag \
  --draft

remote_dmg_digest="$(gh release view "$TAG" --repo "$REPO" --json assets --jq ".assets[] | select(.name == \"$(basename "$DMG_PATH")\") | .digest")"
remote_appcast_digest="$(gh release view "$TAG" --repo "$REPO" --json assets --jq ".assets[] | select(.name == \"$(basename "$APPCAST_PATH")\") | .digest")"
if [[ "$remote_dmg_digest" != "sha256:$local_dmg_sha" ]]; then
  fail "uploaded DMG digest mismatch: expected sha256:$local_dmg_sha, got ${remote_dmg_digest:-missing}"
fi
if [[ "$remote_appcast_digest" != "sha256:$local_appcast_sha" ]]; then
  fail "uploaded appcast digest mismatch: expected sha256:$local_appcast_sha, got ${remote_appcast_digest:-missing}"
fi

gh release edit "$TAG" --repo "$REPO" --draft=false --latest
release_info="$(gh release view "$TAG" --repo "$REPO" --json isDraft,url --jq '[.isDraft, .url] | @tsv')"
IFS=$'\t' read -r release_is_draft release_url <<< "$release_info"
if [[ "$release_is_draft" != "false" || -z "$release_url" ]]; then
  fail "release did not reach the published state"
fi
echo "release=$release_url"
echo "dmg_sha256=$local_dmg_sha"
echo "appcast_sha256=$local_appcast_sha"
