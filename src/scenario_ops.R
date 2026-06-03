# =============================================================================
# scenario_ops.R — the counterfactual operations engine
# =============================================================================
#
# A scenario = a synthetic future revision = the baseline AuthoritySpec set with a
# small list of OPERATIONS applied before the calculator runs (docs/authority_spec.md).
# "baseline = the empty scenario" — an empty operations list is a no-op.
#
# apply_operations(specs, ops) returns a mutated authority_spec_set; the build
# then runs calculate_rates_for_revision(..., specs = mutated) and recomputes.
#
# PHASE 2 SCOPE — only operations the calculator currently READS off the spec:
#   * set_country_scope / disable / set_active for STRUCTURE-CONFIGURED authorities
#     whose country scope the calc reads from the spec: section_301, section_201.
#   * The flagship: `set_country_scope section_301 -> {China, Vietnam}` (301 -> VN).
#
# NOT YET SUPPORTED (error loudly — never a silent no-op):
#   * Any op on section_232 / ieepa_* / section_122 rates: those rates still come
#     from the embedded raw objects (232/ieepa) or internal extraction (s122), not
#     normalized spec fields — making them spec-authoritative is the deferred
#     Phase 7 (embed/seed) work. `disable` of these needs that first.
#   * add_program (no-Ch99 seeding), set_rate/floor on embed authorities,
#     set_product_scope. Deferred.
#
# Depends on src/authority_spec.R (constructors, validate_spec_set, %||%).
# =============================================================================

# Authorities whose country scope the Phase-2 calculator reads from the spec.
SCOPE_DRIVEN_AUTHORITIES <- c('section_301', 'section_201')

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Apply a list of operations to a spec set, in listed order.
#'
#' @param specs an authority_spec_set (the baseline)
#' @param operations list of operation records, each a list with `$op`,
#'   `$authority`, and verb-specific fields (`$country_scope`, `$program`, ...)
#' @return the mutated, re-validated authority_spec_set
apply_operations <- function(specs, operations = list()) {
  if (!is_authority_spec_set(specs)) stop('apply_operations: not an authority_spec_set')
  for (i in seq_along(operations)) {
    specs <- apply_operation(specs, operations[[i]], i)
  }
  validate_spec_set(specs)
  specs
}

#' Apply one operation. Dispatches on `op$op`. Fail-loud on anything unsupported.
apply_operation <- function(specs, op, idx = NA_integer_) {
  verb <- op$op %||% stop(sprintf('operation[%s]: missing `op` verb', idx))
  auth <- op$authority %||% stop(sprintf('operation[%s] (%s): missing `authority`', idx, verb))
  if (is.null(specs[[auth]])) {
    stop(sprintf('operation[%s] (%s): unknown authority "%s" (have: %s)',
                 idx, verb, auth, paste(names(specs), collapse = ', ')))
  }

  switch(verb,
    set_country_scope = op_set_country_scope(specs, op, idx),
    set_active        = op_set_active(specs, op, idx),
    disable           = op_disable(specs, op, idx),
    stop(sprintf('operation[%s]: verb "%s" is not supported in Phase 2. Supported: %s. ',
                 idx, verb, 'set_country_scope, set_active, disable'),
         'Rate/coverage ops on 232/IEEPA/s122 need the Phase 7 embed/seed work.')
  )
}

#' Locate a program within an authority by id (or the sole program if id omitted).
.find_program_index <- function(spec, program_id, idx, verb) {
  progs <- spec$programs
  if (is.null(program_id)) {
    if (length(progs) != 1L) {
      stop(sprintf('operation[%s] (%s): authority "%s" has %d programs — specify `program`',
                   idx, verb, spec$authority, length(progs)))
    }
    return(1L)
  }
  ids <- vapply(progs, function(p) p$id %||% NA_character_, character(1))
  pos <- which(ids == program_id)
  if (length(pos) != 1L) {
    stop(sprintf('operation[%s] (%s): program "%s" not found in "%s" (have: %s)',
                 idx, verb, program_id, spec$authority, paste(ids, collapse = ', ')))
  }
  pos
}

#' Guard: the authority's scope must actually be read by the calc (Phase 2).
.require_scope_driven <- function(auth, idx, verb) {
  if (!auth %in% SCOPE_DRIVEN_AUTHORITIES) {
    stop(sprintf(paste0('operation[%s] (%s): authority "%s" is not scope-driven in ',
                        'Phase 2 — only %s have their country scope read from the spec. ',
                        '(232/IEEPA/s122 scope is embed/internal; deferred to Phase 7.)'),
                 idx, verb, auth, paste(SCOPE_DRIVEN_AUTHORITIES, collapse = ', ')))
  }
}

#' set_country_scope — replace a program's country_scope (the re-scope verb).
#' Flagship: 301 -> {China, Vietnam}. `op$country_scope` = {include, exclude}.
op_set_country_scope <- function(specs, op, idx) {
  .require_scope_driven(op$authority, idx, 'set_country_scope')
  scope <- op$country_scope %||% stop(sprintf('operation[%s] (set_country_scope): missing `country_scope`', idx))
  pos <- .find_program_index(specs[[op$authority]], op$program, idx, 'set_country_scope')
  specs[[op$authority]]$programs[[pos]]$country_scope <- scope
  specs
}

#' disable — zero an authority by emptying its country scope (scope-driven only
#' in Phase 2). The calc then applies it to no countries (e.g. rate_301 -> 0).
op_disable <- function(specs, op, idx) {
  .require_scope_driven(op$authority, idx, 'disable')
  for (pos in seq_along(specs[[op$authority]]$programs)) {
    specs[[op$authority]]$programs[[pos]]$country_scope <- list(include = character(0))
  }
  specs
}

#' set_active — change a program's (or authority's) active window {from, until}.
#' Read by the calc for IEEPA invalidation (active.until); from/until may be NA.
op_set_active <- function(specs, op, idx) {
  active <- op$active %||% stop(sprintf('operation[%s] (set_active): missing `active`', idx))
  if (is.null(op$program)) {
    specs[[op$authority]]$active <- modifyList(specs[[op$authority]]$active %||% list(), active)
  } else {
    pos <- .find_program_index(specs[[op$authority]], op$program, idx, 'set_active')
    specs[[op$authority]]$programs[[pos]]$active <-
      modifyList(specs[[op$authority]]$programs[[pos]]$active %||% list(), active)
  }
  specs
}
