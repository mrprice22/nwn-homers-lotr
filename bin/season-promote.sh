#!/usr/bin/env bash
# Promote this DEV repo's tree into a season's production repo, and rebuild it.
#
# This is the deploy path. Development happens in the dev realm only; a season's
# repo is a DERIVED artifact = dev's tree + that season's own season block.
# Nothing is ever authored in a production repo.
#
#   bin/season-promote.sh --to ../nwn_homers_lotr_s2
#
# ## Why a tree copy and not git
#
# The old two-repo model (season-cutover-guide.md 5a) carried changes with
# `git cherry-pick` across an orphan cut. That is right for a repo you freeze
# ONCE: a handful of emergency fixes crossing during a short overlap. It does
# not survive a permanent dev realm, where every release crosses and the two
# histories never rejoin - you would be cherry-picking every commit, forever,
# and reconciling the conflicts by hand each time.
#
# So the unit of promotion is the TREE, not the commit. Production's git history
# becomes a series of "Promote from dev @<sha>" commits, which is an honest
# description of what it is. Its full development history already lives here, in
# the dev repo, and continues to.
#
# ## The contract this enforces
#
# rsync runs with --delete over the promoted paths, so **an edit made directly
# in a production repo is destroyed by the next promotion**. That is deliberate
# and it is the whole point: fix it in dev, promote. If it were not enforced,
# production would slowly acquire un-reviewed divergence that dev knows nothing
# about, which is exactly the state the dev realm exists to prevent.
#
# The corollary is that anything a season legitimately owns must be on the
# NEVER list below, not merely "not edited in dev".
#
# Usage:
#   bin/season-promote.sh --to DIR                      # dry run
#   bin/season-promote.sh --to DIR --apply --season N   # promote, rebrand, rebuild
#   ...  --allow-hot    target's server is running and you mean it
#   ...  --no-build     sync + rebrand only, no repack
#
# --season N is mandatory with --apply and must match the target's SEASON_NUM.
# It is the guard against a mistyped --to landing on the wrong live server.
set -euo pipefail

DEV_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NWN_MANAGER_BIN=${NWN_MANAGER_BIN:-/var/home/james/GIT/nwn_manager/bin}

TARGET=""
APPLY=0
ALLOW_HOT=0
BUILD=1
WANT_SEASON=""

while (($#)); do
  case "$1" in
    --to)        TARGET=${2:-}; shift 2 ;;
    --season)    WANT_SEASON=${2:-}; shift 2 ;;
    --apply)     APPLY=1; shift ;;
    --allow-hot) ALLOW_HOT=1; shift ;;
    --no-build)  BUILD=0; shift ;;
    -h|--help)   sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "error: unknown arg: $1" >&2; exit 2 ;;
  esac
done

die() { echo "season-promote: error: $*" >&2; exit 1; }
note() { echo "  $*"; }

[[ -n $TARGET ]] || die "--to DIR is required"
TARGET=$(cd "$TARGET" 2>/dev/null && pwd) || die "target dir not found: $TARGET"
[[ $TARGET != "$DEV_ROOT" ]] || die "refusing to promote a repo into itself"

# ---------------------------------------------------------------- what moves --
# ALLOWLIST, not a denylist. A new top-level file added in dev is NOT promoted
# until it is named here, which fails safe: the alternative (deny-listing) means
# every new file silently ships to production the moment someone creates it.
PROMOTE=(
  unpacked          # the module source itself
  bin               # the tooling, including this script and season-*.py
  tests             # the build gates - production must run the same ones
  systemd           # unit templates (instance name comes from the directory)
  csharp            # Anvil plugin source
  hak_2da           # 2da sources for lotr_rules.hak
  docs.manual       # hand-written wiki pages folded into docs/ at build
  wiki-theme        # wiki styling
  .nwnx_includes    # NWNX script headers the compiler needs
  roadmap.yaml      # one backlog, in dev; production gets it at promotion
)

# NEVER promoted. Each of these is owned by the environment it lives in, and
# copying dev's copy over production's would break that environment.
#
#   server.env            the season block itself - the whole point
#   server.env.local      secrets + NWNSYNC_PUBLIC_URL, gitignored, per-env
#   nasher.cfg            module/artifact names, rewritten by season-brand.py
#   wrangler.jsonc        Cloudflare worker name; two repos sharing one collides
#   src/                  index.js carries the worker's canonical host
#   index.html            wiki landing page, carries host + connect string
#   docs/                 each environment publishes its OWN generated wiki
#   .nasher/              build cache + that repo's install path
#   .git/                 obviously
#   dist/ tlk/ *.mod      build outputs
#   module-index/         generated indexes, rebuilt per repo
#   roadmap-merit-aliases.json   holds CD keys, gitignored
#
# Note src/, nasher.cfg and wrangler.jsonc are all season-brand.py OUTPUTS: the
# target regenerates them from its own season block in step 4, so not copying
# them is not a gap.

# ------------------------------------------------------------------ preflight --
echo "season-promote"
echo "  from: $DEV_ROOT"
echo "  to:   $TARGET"
echo

read_var() {  # read_var FILE KEY - bash-ish KEY=VALUE with trailing comments
  sed -n "s/^[[:space:]]*\(export[[:space:]]\+\)\?$2[[:space:]]*=[[:space:]]*//p" "$1" \
    | head -1 | sed 's/[[:space:]]\+#.*$//; s/^"\(.*\)"$/\1/; s/^'\''\(.*\)'\''$/\1/'
}

[[ -f $DEV_ROOT/server.env ]] || die "no server.env in $DEV_ROOT"
[[ -f $TARGET/server.env   ]] || die "no server.env in $TARGET (is that a season repo?)"

DEV_ROLE=$(read_var "$DEV_ROOT/server.env" SEASON_ROLE)
TGT_ROLE=$(read_var "$TARGET/server.env" SEASON_ROLE)
TGT_NUM=$(read_var "$TARGET/server.env" SEASON_NUM)
TGT_CONTAINER=$(read_var "$TARGET/server.env" NWN_CONTAINER_NAME)

note "dev role:    ${DEV_ROLE:-unset}"
note "target role: ${TGT_ROLE:-unset} (season ${TGT_NUM:-?})"
echo

# The source must be the dev realm. Promoting *out of* a live season would make
# whatever drifted into production the new source of truth for everything.
[[ $DEV_ROLE == dev ]] || die \
  "this repo has SEASON_ROLE='${DEV_ROLE:-unset}', not 'dev'. Promotion runs FROM the dev realm only."

# And the target must be a season. `archive` is excluded because a retired
# season is frozen by policy; `dev` because there is only one.
case "$TGT_ROLE" in
  live|test) ;;
  archive) die "target is SEASON_ROLE=archive - a retired season is frozen. Change its role deliberately if you really mean to ship to it." ;;
  *) die "target has SEASON_ROLE='${TGT_ROLE:-unset}'; promotion targets must be live or test." ;;
esac

# Say out loud which season you meant. Role alone is not enough of a guard: at
# any moment there is a `live` season and there may be a `test` one, several
# sibling directories differing by one character, and a promotion into the wrong
# one overwrites a real server's module with another season's content. Making
# the operator restate the number turns a mistyped --to into a refusal instead
# of an outage.
if (( APPLY )) && [[ -z $WANT_SEASON ]]; then
  die "--apply requires --season ${TGT_NUM:-N} to confirm you mean $(basename "$TARGET") (season ${TGT_NUM:-?}, role $TGT_ROLE)."
fi
if [[ -n $WANT_SEASON && $WANT_SEASON != "$TGT_NUM" ]]; then
  die "--season $WANT_SEASON does not match $(basename "$TARGET"), which is season ${TGT_NUM:-unset}."
fi

# A dirty dev tree means promoting something that is not committed anywhere -
# production would carry code with no reviewable history behind it.
if [[ -n $(git -C "$DEV_ROOT" status --porcelain) ]]; then
  die "dev working tree is dirty. Commit or stash first - promotion must be traceable to a dev commit."
fi

# The target may legitimately have docs/ churn: its own wiki publisher commits
# there unattended. Anything ELSE uncommitted is local divergence about to be
# destroyed by --delete, so stop and let a human look at it.
TGT_DIRTY=$(git -C "$TARGET" status --porcelain -- . ':!docs' ':!docs/*' || true)
if [[ -n $TGT_DIRTY ]]; then
  echo "target has uncommitted changes outside docs/:" >&2
  echo "$TGT_DIRTY" | sed 's/^/    /' >&2
  die "refusing to overwrite them. Promotion deletes local edits in production by design - if these matter, port them to dev first."
fi

# A running server holds the module and its DBs open; swapping the .mod under it
# does nothing until restart, and a mid-session hak/tlk change is worse.
if [[ -n ${TGT_CONTAINER:-} ]] && (( ! ALLOW_HOT )) \
   && podman container exists "$TGT_CONTAINER" 2>/dev/null \
   && [[ $(podman inspect -f '{{.State.Running}}' "$TGT_CONTAINER" 2>/dev/null) == true ]]; then
  die "target container '$TGT_CONTAINER' is running. Stop it first, or pass --allow-hot if you intend to rebuild under a live server."
fi

# Dev's own tree must be self-consistent before it becomes the source for
# somewhere else. These are the same gates the repack runs.
echo "checking dev gates..."
python3 "$DEV_ROOT/bin/season-brand.py"   --check >/dev/null || die "dev season-brand --check failed; run --apply in dev first"
python3 "$DEV_ROOT/bin/season-profile.py" --check >/dev/null || die "dev season-profile --check failed; run --apply in dev first"
note "season-brand + season-profile OK"
echo

DEV_SHA=$(git -C "$DEV_ROOT" rev-parse --short HEAD)
DEV_DESC=$(git -C "$DEV_ROOT" log -1 --format='%s' HEAD)

# --------------------------------------------------------------------- rsync --
RSYNC_ARGS=(-a --delete --itemize-changes
            --exclude='.git' --exclude='__pycache__' --exclude='*.pyc')
(( APPLY )) || RSYNC_ARGS+=(--dry-run)

echo "syncing $( ((APPLY)) || echo '(DRY RUN) ')${#PROMOTE[@]} path(s)..."
CHANGED=0
for p in "${PROMOTE[@]}"; do
  [[ -e $DEV_ROOT/$p ]] || { note "skip $p (not present in dev)"; continue; }
  src="$DEV_ROOT/$p"; [[ -d $src ]] && src="$src/"
  dst="$TARGET/$p";   [[ -d $DEV_ROOT/$p ]] && { mkdir -p "$dst"; dst="$dst/"; }
  out=$(rsync "${RSYNC_ARGS[@]}" "$src" "$dst" | grep -v '^\.d\.\.t\.\.\.\.\.\. \./$' || true)
  n=$(printf '%s' "$out" | grep -c . || true)
  CHANGED=$((CHANGED + n))
  if ((n)); then
    note "$p: $n change(s)"
    printf '%s\n' "$out" | head -12 | sed 's/^/      /'
    ((n > 12)) && echo "      ... and $((n - 12)) more"
  fi
done
echo
note "total: $CHANGED change(s)"
echo

if (( ! APPLY )); then
  echo "DRY RUN - nothing written. Re-run with --apply to promote."
  exit 0
fi

# ------------------------------------------------- rebrand + reprofile target --
# This is what makes a tree branded for DEV correct for wherever it landed.
# Both scripts are shape-matched and idempotent, so they rewrite dev's values to
# the target's regardless of what they previously said.
echo "rebranding target from its own season block..."
python3 "$TARGET/bin/season-brand.py"   --apply | sed 's/^/    /'
python3 "$TARGET/bin/season-profile.py" --apply | sed 's/^/    /'

# Verify rather than trust: if the target is live, its cheats MUST now be off.
python3 "$TARGET/bin/season-brand.py"   --check >/dev/null || die "target still fails season-brand --check after --apply"
python3 "$TARGET/bin/season-profile.py" --check >/dev/null || die "target still fails season-profile --check after --apply"
echo

# ------------------------------------------------------------------- roadmap --
# roadmap.yaml rode along in the sync. Regenerate the target's public page and
# push the same data into ITS in-game Recent Updates sign - roadmapdb lives
# under the target's own NWN_HOME_DIR, so this cannot be done from dev.
echo "refreshing target roadmap..."
( cd "$TARGET" && python3 bin/gen-roadmap.py >/dev/null 2>&1 ) \
  || echo "    WARN: gen-roadmap.py failed in target (page not regenerated)"
( cd "$TARGET" && python3 bin/publish-roadmap-db.py >/dev/null 2>&1 ) \
  || echo "    WARN: publish-roadmap-db.py failed (in-game Recent Updates sign may be stale)"
echo

# --------------------------------------------------------------------- build --
if (( BUILD )); then
  echo "rebuilding target module..."
  BUILD_LOG=$(mktemp)
  if ! "$NWN_MANAGER_BIN/repack-homers-lotr" --project "$TARGET" >"$BUILD_LOG" 2>&1; then
    sed 's/^/    /' "$BUILD_LOG" | tail -30
    die "repack failed in target - production NOT updated"
  fi

  # nasher's overwrite/continue prompts are force-answered yes by the wrapper,
  # so a module with FAILED SCRIPT COMPILES still packs, still installs, and
  # still exits 0. That is survivable when a human is watching the output; it is
  # not survivable in a deploy path. Read the compiler's own tally instead.
  if grep -qiE '^Compile Error|is not a valid|longer than 16 characters' "$BUILD_LOG" \
     || grep -qiE 'Results:.*[1-9][0-9]* errored' "$BUILD_LOG" \
     || grep -qi 'Warning: Compiled only' "$BUILD_LOG"; then
    echo "    --- compiler output ---"
    grep -iE '^Compile Error|is not a valid|longer than 16|Results:|Warning: Compiled' "$BUILD_LOG" \
      | head -25 | sed 's/^/    /'
    die "target module has SCRIPT COMPILE ERRORS. It may already be installed - do NOT start the server on it. Fix in dev and re-promote. Full log: $BUILD_LOG"
  fi
  grep -iE 'Results:|Success: packed|installed to' "$BUILD_LOG" | sed 's/^/    /' || true
  rm -f "$BUILD_LOG"
  echo
fi

# ---------------------------------------------------------------- record it ---
echo "recording the promotion..."
( cd "$TARGET"
  git add -A -- . ':!docs' 2>/dev/null || git add -A
  if git diff --cached --quiet; then
    note "target tree unchanged - nothing to commit"
  else
    git commit -q -m "Promote from dev @${DEV_SHA}

${DEV_DESC}

Tree promoted by bin/season-promote.sh from ${DEV_ROOT}.
Rebranded for season ${TGT_NUM} (role=${TGT_ROLE}) by season-brand.py +
season-profile.py; every season-scoped value is this repo's own."
    note "committed $(git rev-parse --short HEAD)"
  fi
)

TAG="promote/s${TGT_NUM}/$(date +%Y-%m-%d-%H%M)"
git -C "$DEV_ROOT" tag -f "$TAG" >/dev/null
note "tagged dev as $TAG"
echo
echo "done. Promoted dev @${DEV_SHA} -> season ${TGT_NUM}."
echo "  what is in dev but not yet live:  git -C $DEV_ROOT log ${TAG}..HEAD --oneline"
echo "  next: push the target repo (Cloudflare builds its wiki on push), then"
echo "        restart its server:  systemctl --user restart nwn-season-server@$(basename "$TARGET")"
