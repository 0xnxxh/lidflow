#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/lidflow-publish-test.XXXXXX)"
TEST_REPO="$TEST_DIR/repo"
TEST_REMOTE="$TEST_DIR/origin.git"
TEST_MARKER="$TEST_DIR/release-check-ran"
TEST_RELEASE_STATE="$TEST_DIR/release-state"
TEST_GH_LOG="$TEST_DIR/gh.log"

cleanup() {
  if [[ "${KEEP_RELEASE_TEST_DIR:-}" == "1" ]]; then
    echo "kept publish test directory: $TEST_DIR" >&2
  else
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$TEST_REPO/script" "$TEST_REPO/test-bin"
cp "$ROOT_DIR/script/publish_release.sh" "$TEST_REPO/script/"
cp "$ROOT_DIR/script/version.sh" "$TEST_REPO/script/"
printf '9.9.9\n' > "$TEST_REPO/VERSION"
printf '999\n' > "$TEST_REPO/BUILD_NUMBER"
printf '# LidFlow v9.9.9\n' > "$TEST_REPO/RELEASE_NOTES.md"
printf 'dist/\n' > "$TEST_REPO/.gitignore"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "run\n" >> "${RELEASE_TEST_MARKER:?}"' \
  'root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"' \
  'mkdir -p "$root_dir/dist"' \
  'printf "release dmg\n" > "$root_dir/dist/LidFlow-v9.9.9.dmg"' \
  'printf "release appcast\n" > "$root_dir/dist/appcast.xml"' \
  > "$TEST_REPO/script/release_check.sh"
chmod +x "$TEST_REPO/script/release_check.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$*" >> "${RELEASE_TEST_GH_LOG:?}"' \
  'command_name="${1:-} ${2:-}"' \
  'if [[ "$command_name" == "release view" ]]; then' \
  '  if [[ "${RELEASE_TEST_SCENARIO:-}" == "existing" ]]; then printf "v9.9.9\n"; exit 0; fi' \
  '  if [[ "${RELEASE_TEST_SCENARIO:-}" == "lookup-error" ]]; then printf "network unavailable\n" >&2; exit 1; fi' \
  '  if [[ ! -f "${RELEASE_TEST_RELEASE_STATE:?}" ]]; then printf "release not found\n" >&2; exit 1; fi' \
  '  if [[ "$*" == *"--json assets"* && "$*" == *"LidFlow-v9.9.9.dmg"* ]]; then' \
  '    sha="$(shasum -a 256 "${RELEASE_TEST_REPO:?}/dist/LidFlow-v9.9.9.dmg" | awk '\''{print $1}'\'')"' \
  '    printf "sha256:%s\n" "$sha"' \
  '  elif [[ "$*" == *"--json assets"* && "$*" == *"appcast.xml"* ]]; then' \
  '    sha="$(shasum -a 256 "${RELEASE_TEST_REPO:?}/dist/appcast.xml" | awk '\''{print $1}'\'')"' \
  '    printf "sha256:%s\n" "$sha"' \
  '  elif [[ "$*" == *"--json isDraft,url"* ]]; then' \
  '    printf "false\thttps://example.invalid/releases/v9.9.9\n"' \
  '  fi' \
  '  exit 0' \
  'fi' \
  'if [[ "$command_name" == "release create" ]]; then' \
  '  [[ "$*" == *"--draft"* && "$*" == *"--verify-tag"* ]]' \
  '  printf "draft\n" > "${RELEASE_TEST_RELEASE_STATE:?}"' \
  '  exit 0' \
  'fi' \
  'if [[ "$command_name" == "release edit" ]]; then' \
  '  [[ "$*" == *"--draft=false"* && "$*" == *"--latest"* ]]' \
  '  printf "published\n" > "${RELEASE_TEST_RELEASE_STATE:?}"' \
  '  exit 0' \
  'fi' \
  'exit 64' \
  > "$TEST_REPO/test-bin/gh"
chmod +x "$TEST_REPO/test-bin/gh"

git -C "$TEST_REPO" init -q -b main
git -C "$TEST_REPO" config user.name "LidFlow Tests"
git -C "$TEST_REPO" config user.email "lidflow-tests@example.invalid"
git -C "$TEST_REPO" add .
git -C "$TEST_REPO" commit -qm "test fixture"
git init -q --bare "$TEST_REMOTE"
git -C "$TEST_REPO" remote add origin "$TEST_REMOTE"
git -C "$TEST_REPO" push -qu origin main

run_publish() {
  env -u APP_VERSION -u BUILD_NUMBER \
    PATH="$TEST_REPO/test-bin:$PATH" \
    RELEASE_TEST_GH_LOG="$TEST_GH_LOG" \
    RELEASE_TEST_MARKER="$TEST_MARKER" \
    RELEASE_TEST_RELEASE_STATE="$TEST_RELEASE_STATE" \
    RELEASE_TEST_REPO="$TEST_REPO" \
    RELEASE_TEST_SCENARIO="$1" \
    CONFIRM_PUBLISH=1 \
    "$TEST_REPO/script/publish_release.sh"
}

output_path="$TEST_DIR/output.log"
if run_publish existing >"$output_path" 2>&1; then
  echo "publish unexpectedly succeeded for an existing release" >&2
  exit 1
fi

if [[ -e "$TEST_MARKER" ]]; then
  echo "publish rebuilt artifacts before rejecting an existing release" >&2
  exit 1
fi

if ! grep -q "release already exists" "$output_path"; then
  echo "publish did not explain that the release already exists" >&2
  exit 1
fi

if run_publish lookup-error >"$output_path" 2>&1; then
  echo "publish unexpectedly continued after a release lookup failure" >&2
  exit 1
fi

if [[ -e "$TEST_MARKER" ]]; then
  echo "publish rebuilt artifacts after a release lookup failure" >&2
  exit 1
fi

if ! grep -q "could not verify that v9.9.9 is unpublished" "$output_path"; then
  echo "publish did not report the release lookup failure" >&2
  exit 1
fi

mkdir "$TEST_REPO/.git/lidflow-release.lock"
if run_publish new >"$output_path" 2>&1; then
  echo "publish unexpectedly succeeded while the release lock was held" >&2
  exit 1
fi
rmdir "$TEST_REPO/.git/lidflow-release.lock"

if [[ -e "$TEST_MARKER" ]]; then
  echo "publish ran the release check while another release held the lock" >&2
  exit 1
fi

if ! grep -q "another release is already running" "$output_path"; then
  echo "publish did not explain that another release held the lock" >&2
  exit 1
fi

: > "$TEST_GH_LOG"
run_publish new >"$output_path" 2>&1

if [[ "$(wc -l < "$TEST_MARKER" | tr -d '[:space:]')" != "1" ]]; then
  echo "publish must run the release check exactly once" >&2
  exit 1
fi

if [[ "$(<"$TEST_RELEASE_STATE")" != "published" ]]; then
  echo "publish did not promote the verified draft" >&2
  exit 1
fi

if [[ "$(git -C "$TEST_REPO" rev-parse 'v9.9.9^{commit}')" != "$(git -C "$TEST_REPO" rev-parse HEAD)" ]]; then
  echo "publish tag does not point to HEAD" >&2
  exit 1
fi

if [[ "$(git -C "$TEST_REPO" ls-remote origin refs/tags/v9.9.9 | awk '{print $1}')" != "$(git -C "$TEST_REPO" rev-parse v9.9.9)" ]]; then
  echo "publish did not push the annotated tag" >&2
  exit 1
fi

if ! grep -q "release create.*--verify-tag.*--draft" "$TEST_GH_LOG"; then
  echo "publish did not create a verified draft release" >&2
  exit 1
fi

if ! grep -q "release edit.*--draft=false.*--latest" "$TEST_GH_LOG"; then
  echo "publish did not publish the verified draft" >&2
  exit 1
fi

if ! grep -q "release=https://example.invalid/releases/v9.9.9" "$output_path"; then
  echo "publish did not report the final release URL" >&2
  exit 1
fi

echo "Publish release tests passed"
