#!/usr/bin/env bash
# Publishes the .deb(s) in $INCOMING to the gh-pages branch (flat APT repo for Sileo).  Env: GH_TOKEN GITHUB_REPOSITORY GITHUB_SHA GITHUB_RUN_ID RUN_NUMBER
# COMMIT_SUBJECT BACKFILL(=true: also publish the previous successful builds of the branch whose artifacts still exist) PACKAGE_ID.
# Parallel runs race on the branch: each attempt starts from a fresh clone and `add` is idempotent, a rejected push is simply retried.
set -euo pipefail
INCOMING="${INCOMING:-incoming}"
PACKAGE_ID="${PACKAGE_ID:-com.infernowolf19.backport162}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE="${REMOTE_URL:-https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
SUBJECT="${COMMIT_SUBJECT:-}"
[ -n "$SUBJECT" ] || SUBJECT="$(git log -1 --format=%s "$GITHUB_SHA" 2>/dev/null || true)"

pick_deb() {   # first .deb below directory $1 whose Package is ours
  local d
  for d in $(find "$1" -name '*.deb' 2>/dev/null | sort); do
    if [ "$(dpkg-deb -f "$d" Package)" = "$PACKAGE_ID" ]; then echo "$d"; return; fi
  done
}

# previous builds (oldest first; a failed download of one old build does not stop the others)
rm -rf bf; mkdir -p bf; : > bf/list.tsv
if [ "${BACKFILL:-}" = "true" ]; then
  gh run list --repo "$GITHUB_REPOSITORY" --workflow build-backport162.yml --branch claude/backport162 --status success --limit 60 \
     --json databaseId,headSha,number,displayTitle,createdAt -q 'reverse | .[] | [.databaseId, .headSha, .number, .createdAt, .displayTitle] | @tsv' > bf/runs.tsv || true
  while IFS=$'\t' read -r id sha num created title; do
    [ -n "$id" ] || continue
    [ "$id" = "$GITHUB_RUN_ID" ] && continue
    mkdir -p "bf/$id"
    gh run download "$id" --repo "$GITHUB_REPOSITORY" -D "bf/$id" >/dev/null 2>&1 || { echo "backfill: run $id (build $num): artifact gone"; continue; }
    deb="$(pick_deb "bf/$id")"
    [ -n "$deb" ] || { echo "backfill: run $id (build $num): no $PACKAGE_ID deb"; continue; }
    printf '%s\t%s\t%s\t%s\t%s\n' "$deb" "$num" "$sha" "$created" "$title" >> bf/list.tsv
  done < bf/runs.tsv
fi
deb="$(pick_deb "$INCOMING")"
[ -n "$deb" ] || { echo "no $PACKAGE_ID deb in $INCOMING"; exit 1; }

attempt() {
  rm -rf site
  if git ls-remote --exit-code --heads "$REMOTE" gh-pages >/dev/null 2>&1; then
    git clone --quiet --depth 1 --branch gh-pages "$REMOTE" site
  else
    mkdir site && git -C site init -q -b gh-pages && git -C site remote add origin "$REMOTE"
  fi
  git -C site config user.name "github-actions[bot]"
  git -C site config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  while IFS=$'\t' read -r bdeb num sha created title; do
    [ -n "$bdeb" ] || continue
    python3 "$HERE/aptrepo.py" site add "$bdeb" --run "$num" --sha "$sha" --subject "$title" --date "$created" || echo "backfill: build $num failed"
  done < bf/list.tsv
  python3 "$HERE/aptrepo.py" site add "$deb" --run "$RUN_NUMBER" --sha "$GITHUB_SHA" --subject "$SUBJECT" --date "$(date -u +%FT%TZ)"
  git -C site add -A
  if git -C site diff --cached --quiet; then echo "nothing to publish"; return 0; fi
  git -C site commit -q -m "repo: build ${RUN_NUMBER} (${GITHUB_SHA::7})"
  git -C site push -q origin HEAD:gh-pages
}

for i in 1 2 3 4 5; do
  if attempt; then echo "published (attempt $i)"; exit 0; fi
  echo "push rejected or failed (attempt $i), retrying from a fresh clone"
  sleep $((i * 4))
done
echo "publishing to gh-pages failed"; exit 1
