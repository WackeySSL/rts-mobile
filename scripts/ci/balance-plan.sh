#!/usr/bin/env bash
# The shard table of the balance run (P190, ADR 0031 sections 5 and 6): prints the matrix of
# .github/workflows/balance.yml's `shards` job, or the names of the sets that its `summarise` job
# merges, for the suite in SUITE. tests/project/test_ci_balance_workflow.gd runs this script and pins the table.
# Usage: bash scripts/ci/balance-plan.sh matrix|sets
# Env:   SUITE   balance (default), gate or custom
#        custom only: LEVELS (default normal,normal), SCENARIOS (default cross), MATCHES (default 20),
#        SEED_START (default 1)
# Output: matrix  one line of JSON, {"include":[{set, levels, scenarios, seed_start, matches, name}, ...]}
#         sets    the set names, space separated; a set's shard reports are build/balance/<set>-*.json
# Sets:  balance runs the five sets of the table below. gate runs the held-out set, seeds 1001-1100. custom
#        plays one set in shards of at most 25 matches and refuses a seed range that reaches 1000-1100 (1000
#        bounds the balance sets and the gate plays 1001-1100, which stay unplayed, section 6; the rerun's
#        1101-1200 is allowed) or whose last seed has more than 9 digits (run-sim-smoke.sh's limit).
# Exit:  0 ok; 2 bad argument or a value that is not valid
# Bash 3.2 compatible.
set -euo pipefail

usage() {
  echo "usage: bash scripts/ci/balance-plan.sh matrix|sets" >&2
}

mode="${1:-}"
if [ $# -ne 1 ] || { [ "$mode" != "matrix" ] && [ "$mode" != "sets" ]; }; then
  usage
  exit 2
fi

suite="${SUITE:-balance}"
rows=()
sets=()

# add SET LEVELS SCENARIOS SEED_START MATCHES: one shard; its report is <SET>-<A>-<B>-<SEED_START>.json.
add() {
  rows+=("{\"set\":\"$1\",\"levels\":\"$2\",\"scenarios\":\"$3\",\"seed_start\":$4,\"matches\":$5,\"name\":\"$1-${2/,/-}-$4\"}")
}

bad() {
  echo "balance-plan: $1" >&2
  exit 2
}

case "$suite" in
  balance)
    sets=(tuning ladder-easy ladder-hard fossil-mirror renew-mirror baseline)
    for s in 1 26 51 76; do add tuning normal,normal cross "$s" 25; done
    add ladder-easy easy,normal cross 1 10
    add ladder-easy normal,easy cross 1 10
    add ladder-hard hard,normal cross 1 10
    add ladder-hard normal,hard cross 1 10
    add fossil-mirror normal,normal fossil-mirror 1 20
    add renew-mirror normal,normal renew-mirror 1 20
    add baseline easy,dummy cross 1 5
    add baseline dummy,easy cross 1 5
    ;;
  gate)
    sets=(gate)
    for s in 1001 1026 1051 1076; do add gate normal,normal cross "$s" 25; done
    ;;
  custom)
    sets=(custom)
    levels="${LEVELS:-normal,normal}"
    scenarios="${SCENARIOS:-cross}"
    matches="${MATCHES:-20}"
    seed_start="${SEED_START:-1}"
    [[ "$levels" =~ ^(easy|normal|hard|dummy),(easy|normal|hard|dummy)$ ]] ||
      bad "LEVELS must be two of easy, normal, hard, dummy, like normal,hard"
    case "$scenarios" in
      cross | derrick | lumen | fossil-mirror | renew-mirror) ;;
      *) bad "SCENARIOS must be cross, derrick, lumen, fossil-mirror or renew-mirror" ;;
    esac
    [[ "$matches" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$matches" -le 200 ] ||
      bad "MATCHES must be 1 to 200"
    [[ "$seed_start" =~ ^[1-9][0-9]{0,8}$ ]] || bad "SEED_START must be a positive integer of at most 9 digits"
    last=$((seed_start + matches - 1))
    if [ "$seed_start" -le 1100 ] && [ "$last" -ge 1000 ]; then
      bad "seeds $seed_start-$last reach 1000-1100 (the gate plays 1001-1100); a custom run never plays them"
    fi
    [ "$last" -le 999999999 ] || bad "seeds $seed_start-$last pass 9 digits, which run-sim-smoke.sh refuses"
    left="$matches"
    seed="$seed_start"
    while [ "$left" -gt 0 ]; do
      n=25
      [ "$left" -ge "$n" ] || n="$left"
      add custom "$levels" "$scenarios" "$seed" "$n"
      seed=$((seed + n))
      left=$((left - n))
    done
    ;;
  *) bad "SUITE must be balance, gate or custom" ;;
esac

if [ "$mode" = "sets" ]; then
  echo "${sets[*]}"
else
  joined="$(printf '%s,' "${rows[@]}")"
  echo "{\"include\":[${joined%,}]}"
fi
