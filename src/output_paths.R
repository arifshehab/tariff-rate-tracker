# =============================================================================
# Output path layout (Phase 5)  —  single source of truth for WHERE outputs go
# =============================================================================
# The build keeps the real ("actual") results separate from named scenario
# ("what-if") results:
#
#   output/
#   |-- actual/      daily/  quality/  etr/  etrs_config/   (+ manifest.json)
#   |-- scenarios/
#   |   `-- <name>/   daily_overall.csv, by_*.csv           (+ manifest.json)
#   `-- logs/        build logs (NOT part of the published layout; unchanged)
#
# Every writer and the publish layer routes through these helpers so the layout
# lives in exactly one place — moving it is a one-file edit, and no consumer can
# silently keep pointing at a stale location.
#
# Override the root via TARIFF_OUTPUT_DIR (used by parity / equivalence harnesses
# that build into a scratch directory). The publish_*.R layer reads from a
# specific repo_root, so every helper also accepts an explicit `root`.

#' Root of the build output tree. Honors TARIFF_OUTPUT_DIR; defaults to output/.
output_root <- function() {
  env <- Sys.getenv('TARIFF_OUTPUT_DIR', unset = '')
  if (nzchar(env)) env else here::here('output')
}

# ---- the "actual" (real, non-scenario) results tree -------------------------
actual_root            <- function(root = output_root()) file.path(root, 'actual')
actual_daily_dir       <- function(root = output_root()) file.path(actual_root(root), 'daily')
actual_quality_dir     <- function(root = output_root()) file.path(actual_root(root), 'quality')
actual_etr_dir         <- function(root = output_root()) file.path(actual_root(root), 'etr')
actual_etrs_config_dir <- function(root = output_root()) file.path(actual_root(root), 'etrs_config')

#' The sections that live under actual/ (drives the publish copy loop).
ACTUAL_SECTIONS <- c('daily', 'quality', 'etr', 'etrs_config')

# ---- the named-scenario ("what-if") tree ------------------------------------
scenarios_root <- function(root = output_root()) file.path(root, 'scenarios')

#' Directory for a single named scenario (e.g. scenario_dir('no_ieepa')).
scenario_dir <- function(name, root = output_root()) file.path(scenarios_root(root), name)

# ---- unchanged-by-Phase-5 locations (kept here for one-stop reference) -------
logs_dir <- function(root = output_root()) file.path(root, 'logs')
