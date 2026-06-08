#!/bin/bash
#
# Config-driven build orchestrator (build output reform).
# =============================================================================
# ONE input: a build-config YAML. ONE output: a timestamped vintage on the
# external interface (model_data_root) containing the `actual` series plus a
# subfolder per scenario. The repository working tree is NEVER written to —
# intermediates stage under <staging_root>/<vintage>/ and are removed after publish.
#
#   bash scripts/submit_build_array.sh --config config/build/example.yaml
#
# Flow:
#   1. Parse the config (scripts/print_build_config.R) + pin ONE vintage.
#   2. For each series in [actual, <scenarios…>]: list-revs (sbatch --wait, to size
#      the array) -> array build -> gather (assemble + downstream), all writing into
#      the external staging tree. Each is afterok-chained; series run concurrently.
#   3. ONE publish job (afterok all gathers): scripts/publish_vintage.R ->
#      write_build_output() emits <model_data_root>/<vintage>/{actual,scenarios/<name>}.
#   4. Cleanup job (afterok publish): rm -rf the staging dir.
# =============================================================================

set -euo pipefail
REPO=/nfs/roberts/project/pi_nrs36/jar335/Repositories/tariff-rate-tracker
cd "$REPO"
mkdir -p "$HOME/slurm-logs"

# ---- args -------------------------------------------------------------------
CONFIG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; echo "usage: $0 --config <build-config.yaml>" >&2; exit 2 ;;
  esac
done
if [ -z "$CONFIG" ]; then
  echo "usage: $0 --config <build-config.yaml>   (e.g. config/build/example.yaml)" >&2
  exit 2
fi
[ -f "$CONFIG" ] || { echo "config not found: $CONFIG" >&2; exit 2; }

# ---- module env (for the Rscript config bridge + job wraps) -----------------
if [ -f /etc/profile.d/z01_lmodinit.sh ]; then source /etc/profile.d/z01_lmodinit.sh
elif [ -f /etc/profile.d/lmod.sh ]; then source /etc/profile.d/lmod.sh; fi
module load R/4.4.2-gfbf-2024a 2>/dev/null || true
MODLOAD='if [ -f /etc/profile.d/z01_lmodinit.sh ]; then source /etc/profile.d/z01_lmodinit.sh; elif [ -f /etc/profile.d/lmod.sh ]; then source /etc/profile.d/lmod.sh; fi; module purge; module load R/4.4.2-gfbf-2024a'

# ---- resolve config (single source: bash + R agree) -------------------------
eval "$(Rscript scripts/print_build_config.R "$CONFIG")"
VINTAGE=$(date +%Y-%m-%d-%H)
STAGING="$STAGING_ROOT/$VINTAGE"

echo "=========================================================="
echo "Build config : $CONFIG"
echo "Vintage      : $VINTAGE"
echo "Interface    : $MODEL_DATA_ROOT"
echo "Staging      : $STAGING   (external; removed after publish)"
echo "Series       : actual ${SCENARIOS:-<none>}"
echo "=========================================================="

# ---- guard: nothing may resolve inside the repo working tree ----------------
assert_external() {  # $1=path  $2=label
  local rp; rp="$(readlink -m "$1")"
  case "$rp/" in
    "$REPO"/*) echo "REFUSING: $2 ($1 -> $rp) is inside the repo working tree" >&2; exit 1 ;;
  esac
}
assert_external "$STAGING" STAGING

# ---- per-step flags from config ---------------------------------------------
LIST_ARGS=""; BUILD_REVISION_ARGS=""; GATHER_ARGS=""
if [ "${USE_HTS_DATES:-0}" = "1" ]; then
  LIST_ARGS+=" --use-hts-dates"; BUILD_REVISION_ARGS+=" --use-hts-dates"; GATHER_ARGS+=" --use-hts-dates"
fi
if [ "${WEIGHT_MODE:-required}" = "unweighted" ]; then
  BUILD_REVISION_ARGS+=" --unweighted"; GATHER_ARGS+=" --unweighted"
fi
[ "${ALLOW_PARTIAL:-0}" = "1" ] && GATHER_ARGS+=" --allow-partial"

# ---- build each series into the staging tree --------------------------------
SERIES_LIST=(actual ${SCENARIOS:-})
GATHER_JOBS=()
BASELINE_TS_DIR="$STAGING/data/timeseries"      # the actual-series snapshots scenarios reuse

for series in "${SERIES_LIST[@]}"; do
  if [ "$series" = "actual" ]; then
    SCEN=""; TS_DIR="$STAGING/data/timeseries"
  else
    SCEN="$series"; TS_DIR="$STAGING/data/timeseries/$series"
  fi
  OUT_DIR="$STAGING/output"
  RL="$STAGING/revlist_${series}.txt"
  RT="$STAGING/timeline_${series}.rds"
  assert_external "$TS_DIR" "TARIFF_TS_DIR[$series]"
  assert_external "$OUT_DIR" "TARIFF_OUTPUT_DIR[$series]"
  mkdir -p "$TS_DIR" "$OUT_DIR"

  echo "--- [$series] list revisions (sbatch --wait) ---"
  TARIFF_SCENARIO="$SCEN" TARIFF_POLICY_PARAMS="$POLICY_PARAMS_PATH" REVLIST="$RL" REV_TIMELINE="$RT" \
    sbatch --wait --job-name="lr-$series" --time=00:15:00 --nodes=1 --ntasks=1 --cpus-per-task=1 --mem=8G \
      --output="$HOME/slurm-logs/lr-$series-%j.out" --error="$HOME/slurm-logs/lr-$series-%j.err" --chdir="$REPO" \
      --wrap="$MODLOAD; Rscript scripts/list_revisions.R$LIST_ARGS" >/dev/null
  N=$(grep -c . "$RL" || true)
  [ "${N:-0}" -ge 1 ] || { echo "ERROR: no revisions for series '$series' in $RL" >&2; exit 1; }
  echo "    $series: $N revisions ($(head -1 "$RL") .. $(tail -1 "$RL"))"

  echo "--- [$series] array build (0-$((N-1))) ---"
  ARRAY_JOB=$(TARIFF_SCENARIO="$SCEN" TARIFF_SERIES="$series" TARIFF_POLICY_PARAMS="$POLICY_PARAMS_PATH" \
    TARIFF_TS_DIR="$TS_DIR" TARIFF_OUTPUT_DIR="$OUT_DIR" REVLIST="$RL" REV_TIMELINE="$RT" \
    BUILD_REVISION_ARGS="$BUILD_REVISION_ARGS" \
    sbatch --parsable --array=0-$((N-1)) scripts/build_array_task.sh)

  echo "--- [$series] gather (afterok:$ARRAY_JOB) ---"
  GJOB=$(TARIFF_SCENARIO="$SCEN" TARIFF_SERIES="$series" TARIFF_POLICY_PARAMS="$POLICY_PARAMS_PATH" \
    TARIFF_TS_DIR="$TS_DIR" TARIFF_OUTPUT_DIR="$OUT_DIR" TARIFF_BASELINE_TS_DIR="$BASELINE_TS_DIR" \
    REV_TIMELINE="$RT" GATHER_ARGS="$GATHER_ARGS" \
    sbatch --parsable --dependency=afterok:"$ARRAY_JOB" scripts/submit_build_gather.sh)
  echo "    array=$ARRAY_JOB gather=$GJOB"
  GATHER_JOBS+=("$GJOB")
done

# ---- single publish, afterok ALL series' gathers ----------------------------
DEP=$(IFS=:; echo "${GATHER_JOBS[*]}")
echo "--- publish vintage $VINTAGE (afterok:$DEP) ---"
PUB_JOB=$(TARIFF_STAGING="$STAGING" TARIFF_VINTAGE="$VINTAGE" TARIFF_MODEL_DATA_ROOT="$MODEL_DATA_ROOT" \
  TARIFF_UPDATE_LATEST="${UPDATE_LATEST:-1}" \
  sbatch --parsable --dependency=afterok:"$DEP" --job-name="publish-$VINTAGE" \
    --time=00:40:00 --nodes=1 --ntasks=1 --cpus-per-task=4 --mem=48G \
    --output="$HOME/slurm-logs/publish-$VINTAGE-%j.out" --error="$HOME/slurm-logs/publish-$VINTAGE-%j.err" \
    --chdir="$REPO" --wrap="$MODLOAD; Rscript scripts/publish_vintage.R")

# ---- cleanup staging, afterok publish (only on success) ---------------------
CLEAN_JOB=$(sbatch --parsable --dependency=afterok:"$PUB_JOB" --job-name="clean-$VINTAGE" \
    --time=00:20:00 --nodes=1 --ntasks=1 --cpus-per-task=1 --mem=4G \
    --output="$HOME/slurm-logs/clean-$VINTAGE-%j.out" --error="$HOME/slurm-logs/clean-$VINTAGE-%j.err" \
    --chdir="$REPO" --wrap="rm -rf '$STAGING' && echo 'removed staging $STAGING'")

echo "=========================================================="
echo "Submitted. publish=$PUB_JOB cleanup=$CLEAN_JOB"
echo "Watch:   squeue -u $USER"
echo "Result:  $MODEL_DATA_ROOT/$VINTAGE/{actual,scenarios/<name>}/  (latest -> $VINTAGE on success)"
echo "Staging $STAGING is removed only if publish succeeds (kept for debug otherwise)."
echo "=========================================================="
