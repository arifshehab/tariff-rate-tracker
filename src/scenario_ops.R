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
# SUPPORTED operations (each READS off the spec; never a silent no-op):
#   * set_country_scope / set_active for the scope-driven authorities (section_301,
#     section_201). Flagship: `set_country_scope section_301 -> {China, Vietnam}`.
#   * set_rate / set_exempt for the rate-bearing authorities: section_232
#     (per-program steel/aluminum/copper/autos/mhd/wood/semiconductors, still a
#     resolved blob until Plank 4a; set_rate recomputes the has_232 OR-gate so a
#     scenario can turn a dormant metal ON) and section_122 (Plank 3: the scalar
#     blanket rate lives in the compositional rate$default layer — set_rate writes
#     it, the calc's value>0 gate turns s122 ON/OFF).
#   * set_rate / set_country_scope / disable for the IEEPA authorities
#     (ieepa_reciprocal, ieepa_fentanyl) — Plank 4b/6: the rate is now structured
#     compositional layers (by_country [+ by_country_type/_eo_* for reciprocal] /
#     carveouts), so set_rate writes a per-country rate (op$country = census code[s]),
#     set_country_scope drops excluded countries (and, for an include={set},
#     restricts to it + turns the reciprocal baseline off), and disable clears every
#     rate layer (calc's by_country/carveouts gate then reads OFF). Baseline =
#     empty ops → parity-safe.
#   * disable — empties scope (301/201), zeros section_232's resolved rates,
#     zeros section_122's rate$default, or clears the IEEPA rate layers (above).
#   * add_program — add a NEW-COVERAGE tariff with no Ch99 backing (Phase 8). The
#     program carries a flat rate + product/country scope, rides rate_other, and is
#     applied by the calc's no-Ch99 seeder (src/new_coverage.R) before stacking.
#
# NOT YET SUPPORTED (error loudly — never a silent no-op):
#   * set_floor (IEEPA universal baseline / phase-1 floor rate): a deferred follow-up.
#   * new-coverage import-weight provisioning for pairs absent from the weight
#     base lives in the ETR step (08), not here.
#
# Depends on src/authority_spec.R (constructors, validate_spec_set, %||%).
# =============================================================================

# Authorities whose country scope the calculator reads from the spec (Phase 2e).
SCOPE_DRIVEN_AUTHORITIES <- c('section_301', 'section_201')

# section_232 (Plank 4a / S1a+S1b+S2): each program's rate is de-blobbed into its
# compositional rate layers — rate$default (base) + rate$by_country (S2 blanket slice:
# steel/aluminum exempt lists + HTS country overrides + config exemptions, merged into
# one per-country overlay). set_rate / disable mutate the per-program defaults (and
# recompute has_232); set_exempt(steel/aluminum) now writes the by_country overlay, and
# disable also clears it. The auto/wood DEAL tibbles are de-blobbed too (S2 deals slice):
# surcharge deals -> the autos/wood program rate$overrides (scope-form), floor deals ->
# rate$floors; disable clears those layers. The NON-rate fields STILL on the residual blob
# (programs[[1]]$rate$resolved, drained in S3/decision-8): auto_has_deals/auto_has_parts
# (has_232 gate inputs), wood_furniture_rate, the derivative rates, auto_exempt, and has_232.
RATE_DRIVEN_AUTHORITIES <- c('section_232')

# Authorities whose scalar rate the calculator reads from the compositional
# rate$default layer (Plank 3, de-blobbed) — set_rate / disable mutate that scalar.
DEFAULT_RATE_AUTHORITIES <- c('section_122')

# IEEPA authorities (Plank 4b/6): de-blobbed into structured per-country layers
# (ieepa_reciprocal: by_country + by_country_type/_eo_rate/_eo_ch99 +
# default_unlisted_rate/_exclude; ieepa_fentanyl: by_country + carveouts). set_rate
# writes a per-country rate (op$country), set_country_scope drops/restricts countries,
# disable clears the layers. Single-program authorities (programs[[1]]).
IEEPA_RATE_AUTHORITIES <- c('ieepa_reciprocal', 'ieepa_fentanyl')

# section_232: program id -> the rate field it owns in the resolved 21-field
# s232_rates list (the thin cut parks the whole list on programs[[1]]; per-program
# normalization is Phase 8, but ops address it by the logical program name here).
S232_RATE_FIELD <- c(steel = 'steel_rate', aluminum = 'aluminum_rate',
                     copper = 'copper_rate', autos = 'auto_rate', mhd = 'mhd_rate',
                     wood = 'wood_rate', semiconductors = 'semi_rate',
                     pharmaceuticals = 'pharma_rate')
# Only the metals/autos primary programs carry country exemption lists.
S232_EXEMPT_FIELD <- c(steel = 'steel_exempt', aluminum = 'aluminum_exempt',
                       autos = 'auto_exempt')

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- resolved-payload accessors (Phase 6d) ----------------------------------
.op_get_resolved <- function(spec) spec$programs[[1]]$rate$resolved
.op_set_resolved <- function(spec, resolved) {
  spec$programs[[1]]$rate$resolved <- resolved
  spec
}
# Recompute the s232 has_232 OR-gate after a rate mutation. S1b: the program rates
# come from the spec's rate$default (resolve_rate), the non-rate terms (auto_has_deals,
# wood_furniture_rate, the two derivative rates) from the residual blob. Mirrors the
# 12-term formula in 05_parse_policy_params.R::extract_section232_rates AND the calc's
# compute_heading_gates — keep all three in lockstep.
.s232_recompute_has_232 <- function(spec) {
  pos <- function(x) isTRUE(x > 0)
  prog_rate <- function(id) {
    progs <- spec$programs
    i <- which(vapply(progs, function(p) identical(p$id, id), logical(1)))
    if (length(i) != 1L) return(0)
    v <- resolve_rate(progs[[i]]$rate)$value
    if (is.na(v)) 0 else v
  }
  r <- .op_get_resolved(spec) %||% list()
  pos(prog_rate('steel')) || pos(prog_rate('aluminum')) || pos(prog_rate('autos')) ||
    isTRUE(r$auto_has_deals) || pos(prog_rate('wood')) || pos(r$wood_furniture_rate) ||
    pos(prog_rate('mhd')) || pos(prog_rate('copper')) || pos(prog_rate('semiconductors')) ||
    pos(prog_rate('pharmaceuticals')) ||
    pos(r$aluminum_derivative_rate) || pos(r$steel_derivative_rate)
}
# Invalidate the cached heading-program activation gates after a 232 rate mutation.
# The calculator reads attr(spec, 'heading_gates') and SKIPS any heading whose gate
# is FALSE; it has a `%||% compute_heading_gates(s232_rates)` fallback (06_calculate_rates.R)
# that recomputes the gates from the (now-mutated) resolved payload whenever the cache
# is absent. Dropping the stale cache here therefore makes a set_rate that activates a
# dormant heading (e.g. copper before its Ch99 codes existed) actually land, and makes
# a disable that zeros a heading correctly flip its gate OFF. Doing it via cache-drop
# (rather than recompute) keeps scenario_ops free of a calculator dependency. Codex F1.
.s232_drop_gate_cache <- function(spec) {
  attr(spec, 'heading_gates') <- NULL
  spec
}

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
  # add_program may omit `authority` — it defaults to the `other` catch-all (Phase 8,
  # honoring op_add_program's documented default); every other verb requires it. Codex F8.
  auth <- op$authority %||%
    (if (identical(verb, 'add_program')) 'other'
     else stop(sprintf('operation[%s] (%s): missing `authority`', idx, verb)))
  if (is.null(specs[[auth]])) {
    stop(sprintf('operation[%s] (%s): unknown authority "%s" (have: %s)',
                 idx, verb, auth, paste(names(specs), collapse = ', ')))
  }

  switch(verb,
    set_country_scope = op_set_country_scope(specs, op, idx),
    set_active        = op_set_active(specs, op, idx),
    disable           = op_disable(specs, op, idx),
    set_rate          = op_set_rate(specs, op, idx),
    set_exempt        = op_set_exempt(specs, op, idx),
    add_program       = op_add_program(specs, op, idx),
    stop(sprintf(paste0('operation[%s]: verb "%s" is not supported. Supported: %s. ',
                        'set_floor is a deferred follow-up.'),
                 idx, verb,
                 'set_country_scope, set_active, disable, set_rate, set_exempt, add_program'))
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
                        '(232/IEEPA/s122 scope is embed/internal; deferred to Phase 6 embed/seed.)'),
                 idx, verb, auth, paste(SCOPE_DRIVEN_AUTHORITIES, collapse = ', ')))
  }
}

#' set_country_scope — replace a program's country_scope (the re-scope verb).
#' Flagship: 301 -> {China, Vietnam}. `op$country_scope` = {include, exclude}.
op_set_country_scope <- function(specs, op, idx) {
  # IEEPA (Plank 4b/6): scope is expressed through the structured per-country rate
  # layers (the calc reads by_country / carveouts, NOT country_scope), so re-scope by
  # editing those layers, not the inert country_scope field.
  if (op$authority %in% IEEPA_RATE_AUTHORITIES) return(.ieepa_set_country_scope(specs, op, idx))
  .require_scope_driven(op$authority, idx, 'set_country_scope')
  scope <- op$country_scope %||% stop(sprintf('operation[%s] (set_country_scope): missing `country_scope`', idx))
  pos <- .find_program_index(specs[[op$authority]], op$program, idx, 'set_country_scope')
  specs[[op$authority]]$programs[[pos]]$country_scope <- scope
  specs
}

#' Re-scope an IEEPA authority by editing its structured rate layers (Plank 4b/6).
#' `exclude` drops those census codes (-> 0) from every per-country layer, and for
#' reciprocal also bars them from the universal-baseline complement
#' (default_unlisted_exclude). `include` = a specific set keeps ONLY those listed
#' countries and, for reciprocal, turns the baseline off (default_unlisted_rate=NULL)
#' so only the included listed countries are subject. include='all' (default) =
#' no include-restriction. The calc reads the edited layers — never a silent no-op.
.ieepa_set_country_scope <- function(specs, op, idx) {
  auth  <- op$authority
  scope <- op$country_scope %||% stop(sprintf(
    'operation[%s] (set_country_scope): missing `country_scope`', idx))
  pr <- specs[[auth]]$programs[[1]]$rate
  drop_codes <- function(pr, codes) {
    codes <- as.character(codes)
    for (f in c('by_country', 'by_country_type', 'by_country_eo_rate', 'by_country_eo_ch99')) {
      v <- pr[[f]]
      if (!is.null(v) && !.rate_is_hollow(v)) pr[[f]] <- v[setdiff(names(v), codes)]
    }
    cv <- pr$carveouts          # fentanyl: drop carve-out rows for excluded census codes
    if (!is.null(cv) && !.rate_is_hollow(cv)) {
      keep <- !(cv$census_code %in% codes)
      pr$carveouts <- if (any(keep))
        list(ch99_code = cv$ch99_code[keep], census_code = cv$census_code[keep], rate = cv$rate[keep])
      else NULL
    }
    pr
  }
  excl <- as.character(scope$exclude %||% character(0))
  if (length(excl)) {
    pr <- drop_codes(pr, excl)
    if (auth == 'ieepa_reciprocal') {
      cur <- pr$default_unlisted_exclude %||% character(0)
      pr$default_unlisted_exclude <- union(as.character(cur), excl)
    }
  }
  incl <- scope$include
  if (!is.null(incl) && !identical(incl, 'all')) {
    incl <- as.character(incl)
    bc <- pr$by_country
    if (!is.null(bc) && !.rate_is_hollow(bc)) {
      drop <- setdiff(names(bc), incl)
      if (length(drop)) pr <- drop_codes(pr, drop)
    }
    if (auth == 'ieepa_reciprocal') pr$default_unlisted_rate <- NULL  # only listed countries apply
  }
  specs[[auth]]$programs[[1]]$rate <- pr
  specs
}

#' disable — turn an authority off. Scope-driven (301/201): empty every program's
#' country scope (calc applies it to no countries). Default-rate (s122) / section_232:
#' zero each program's rate$default (plus 232's residual derivatives/deals/flags) so
#' the calc's value>0 / has_232 gate reads FALSE.
op_disable <- function(specs, op, idx) {
  auth <- op$authority
  if (auth %in% SCOPE_DRIVEN_AUTHORITIES) {
    for (pos in seq_along(specs[[auth]]$programs)) {
      specs[[auth]]$programs[[pos]]$country_scope <- list(include = character(0))
    }
    return(specs)
  }
  # section_122 (Plank 3): zero the compositional rate$default scalar — the calc's
  # value>0 gate then reads OFF (the structured equivalent of has_s122 = FALSE).
  if (auth %in% DEFAULT_RATE_AUTHORITIES) {
    for (pos in seq_along(specs[[auth]]$programs)) {
      specs[[auth]]$programs[[pos]]$rate$default <- 0
    }
    return(specs)
  }
  # IEEPA (Plank 4b/6): clear every structured rate layer so the calc's gate reads
  # OFF — reciprocal (has_active_ieepa <- length(by_country) > 0 => FALSE) and
  # fentanyl (has_fentanyl <- length(by_country) > 0 || !is.null(carveouts) => FALSE).
  if (auth %in% IEEPA_RATE_AUTHORITIES) {
    pr <- specs[[auth]]$programs[[1]]$rate
    for (f in c('by_country', 'by_country_type', 'by_country_eo_rate',
                'by_country_eo_ch99', 'default_unlisted_rate', 'carveouts')) {
      pr[[f]] <- NULL
    }
    specs[[auth]]$programs[[1]]$rate <- pr
    return(specs)
  }
  if (auth %in% RATE_DRIVEN_AUTHORITIES) {   # section_232 (S1b: per-program rate$default + residual blob)
    spec <- specs[[auth]]
    # Zero every program's de-blobbed default rate (the 8 logical programs) AND drop the
    # S2 per-country overlay (else a steel/aluminum by_country override would survive a
    # disable and keep emitting that country's rate).
    for (prog in names(S232_RATE_FIELD)) {
      pos <- .find_program_index(spec, prog, idx, 'disable')
      spec$programs[[pos]]$rate$default    <- 0
      spec$programs[[pos]]$rate$by_country <- NULL
      spec$programs[[pos]]$rate$overrides  <- NULL   # S2 deals: drop scope-form surcharge deals
      spec$programs[[pos]]$rate$floors     <- NULL   # S2 deals: drop floor deals
    }
    # Zero the residual non-rate gate inputs still on the blob, and force has_232 OFF.
    r <- .op_get_resolved(spec)
    if (!is.null(r)) {
      r$aluminum_derivative_rate <- 0
      r$steel_derivative_rate    <- 0
      r$auto_has_deals           <- FALSE
      if (!is.null(r$auto_deal_rates)) r$auto_deal_rates <- r$auto_deal_rates[0, , drop = FALSE]
      if (!is.null(r$wood_deal_rates)) r$wood_deal_rates <- r$wood_deal_rates[0, , drop = FALSE]
      r$has_232 <- FALSE
      spec <- .op_set_resolved(spec, r)
    }
    spec <- .s232_drop_gate_cache(spec)  # Codex F1: gates recompute -> OFF
    specs[[auth]] <- spec
    return(specs)
  }
  stop(sprintf(paste0('operation[%s] (disable): authority "%s" is not disable-able. ',
                      'Supported: %s (scope) + %s (default-rate) + %s (resolved-rate) + %s (IEEPA layers).'),
               idx, auth, paste(SCOPE_DRIVEN_AUTHORITIES, collapse = ', '),
               paste(DEFAULT_RATE_AUTHORITIES, collapse = ', '),
               paste(RATE_DRIVEN_AUTHORITIES, collapse = ', '),
               paste(IEEPA_RATE_AUTHORITIES, collapse = ', ')))
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

#' Guard: the authority's resolved rate payload must be readable by the calc.
.require_rate_driven <- function(auth, idx, verb) {
  if (!auth %in% RATE_DRIVEN_AUTHORITIES) {
    stop(sprintf(paste0('operation[%s] (%s): authority "%s" is not rate-driven — only %s ',
                        'have their resolved rate read from the spec. (IEEPA per-country ',
                        'rate ops are a deferred follow-up; new coverage is Phase 8.)'),
                 idx, verb, auth, paste(RATE_DRIVEN_AUTHORITIES, collapse = ', ')))
  }
}

#' set_rate — set a program's rate in the compositional rate$default layer. Flagship:
#' bump steel. section_232 needs `program` (steel/aluminum/copper/autos/mhd/wood/
#' semiconductors/pharmaceuticals); it writes that program's rate$default and
#' recomputes the residual has_232 gate. section_122 is the single-program default.
op_set_rate <- function(specs, op, idx) {
  auth <- op$authority
  rate <- op$rate %||% stop(sprintf('operation[%s] (set_rate): missing `rate`', idx))
  if (!is.numeric(rate) || length(rate) != 1L || is.na(rate)) {
    stop(sprintf('operation[%s] (set_rate): `rate` must be a single non-NA number', idx))
  }
  # IEEPA (Plank 4b/6): per-country set_rate. `op$country` = census code(s); writes
  # rate$by_country[country] = rate. For reciprocal it's a CLEAN flat surcharge — set
  # by_country_type='surcharge' and drop the country-EO two-term component (eo_rate=0,
  # eo_ch99=NA) so the calc's case_when applies exactly `rate`. The companion maps stay
  # parallel to by_country (the calc indexes them by names(by_country)).
  if (auth %in% IEEPA_RATE_AUTHORITIES) {
    country <- op$country %||% stop(sprintf(
      'operation[%s] (set_rate): %s needs `country` (census code[s])', idx, auth))
    country <- as.character(country)
    if (rate < 0) stop(sprintf('operation[%s] (set_rate): IEEPA rate must be >= 0', idx))
    pr <- specs[[auth]]$programs[[1]]$rate
    .nz <- function(v, num) {            # current layer as a mutable named vector
      if (is.null(v) || .rate_is_hollow(v)) (if (num) numeric(0) else character(0)) else v
    }
    bc <- .nz(pr$by_country, TRUE)
    for (c in country) bc[[c]] <- rate
    pr$by_country <- bc
    if (auth == 'ieepa_reciprocal') {
      bt <- .nz(pr$by_country_type, FALSE)
      er <- .nz(pr$by_country_eo_rate, TRUE)
      ec <- .nz(pr$by_country_eo_ch99, FALSE)
      for (c in country) { bt[[c]] <- 'surcharge'; er[[c]] <- 0; ec[[c]] <- NA_character_ }
      pr$by_country_type    <- bt
      pr$by_country_eo_rate <- er
      pr$by_country_eo_ch99 <- ec
    }
    specs[[auth]]$programs[[1]]$rate <- pr
    return(specs)
  }
  # section_122 (Plank 3): the scalar blanket rate lives in the compositional
  # rate$default layer; the calc gates on value > 0, so writing it here turns
  # s122 ON (or OFF with rate 0). No resolved blob, no has_s122 flag to maintain.
  if (auth %in% DEFAULT_RATE_AUTHORITIES) {
    pos <- .find_program_index(specs[[auth]], op$program, idx, 'set_rate')
    specs[[auth]]$programs[[pos]]$rate$default <- rate
    return(specs)
  }
  # section_232 (Plank 4a / S1b): per-program rate lives in the compositional
  # rate$default layer; the calc reads it via resolve_rate (s232_spec_rate). Write
  # the program's default; recompute the has_232 gate (still a residual field, drained
  # in S3) from the updated spec defaults + the residual flags/derivatives.
  .require_rate_driven(auth, idx, 'set_rate')   # section_232
  spec <- specs[[auth]]
  prog <- op$program %||% stop(sprintf(
    'operation[%s] (set_rate): section_232 needs `program` (one of %s)',
    idx, paste(names(S232_RATE_FIELD), collapse = ', ')))
  if (is.null(S232_RATE_FIELD[[prog]])) stop(sprintf(
    'operation[%s] (set_rate): unknown section_232 program "%s" (have: %s)',
    idx, prog, paste(names(S232_RATE_FIELD), collapse = ', ')))
  pos <- .find_program_index(spec, prog, idx, 'set_rate')
  spec$programs[[pos]]$rate$default   <- rate
  spec$programs[[pos]]$rate$rate_type <- spec$programs[[pos]]$rate$rate_type %||% 'surcharge'
  r <- .op_get_resolved(spec)
  if (!is.null(r)) {
    r$has_232 <- .s232_recompute_has_232(spec)   # spec already carries the new default
    spec <- .op_set_resolved(spec, r)
  }
  spec <- .s232_drop_gate_cache(spec)  # Codex F1
  specs[[auth]] <- spec
  specs
}

#' set_exempt — replace a section_232 program's country exemption list (Phase 6d).
#' `op$countries` = census codes exempt from that program's 232 rate.
op_set_exempt <- function(specs, op, idx) {
  auth <- op$authority
  if (auth != 'section_232') {
    stop(sprintf('operation[%s] (set_exempt): only section_232 supported (got "%s")', idx, auth))
  }
  prog <- op$program %||% stop(sprintf(
    'operation[%s] (set_exempt): needs `program` (one of %s)',
    idx, paste(names(S232_EXEMPT_FIELD), collapse = ', ')))
  if (is.null(S232_EXEMPT_FIELD[[prog]])) stop(sprintf(
    'operation[%s] (set_exempt): no exemption list for section_232 program "%s" (have: %s)',
    idx, prog, paste(names(S232_EXEMPT_FIELD), collapse = ', ')))
  countries <- op$countries %||% stop(sprintf('operation[%s] (set_exempt): missing `countries`', idx))
  spec <- specs[[auth]]
  if (prog %in% c('steel', 'aluminum')) {
    # Plank 4a / S2: steel/aluminum exemptions are de-blobbed into the program's
    # compositional rate$by_country overlay (a 0 entry per exempt census code). Merge the
    # requested countries (census codes) over any baseline by_country, leaving the
    # HTS-override / config-exemption entries intact (set_exempt only adds exempt-0s).
    pos <- .find_program_index(spec, prog, idx, 'set_exempt')
    bc <- spec$programs[[pos]]$rate$by_country
    existing <- if (is.null(bc) || .rate_is_hollow(bc)) NULL else
      stats::setNames(as.numeric(bc), names(bc))
    add <- stats::setNames(rep(0, length(countries)), as.character(countries))
    spec$programs[[pos]]$rate$by_country <- c(existing[setdiff(names(existing), names(add))], add)
    spec <- .s232_drop_gate_cache(spec)
    specs[[auth]] <- spec
    return(specs)
  }
  # autos — still on the residual blob (auto rate is heading-driven, not de-blobbed in S2)
  field <- S232_EXEMPT_FIELD[[prog]]
  r <- .op_get_resolved(spec)
  if (is.null(r)) stop(sprintf('operation[%s] (set_exempt): section_232 has no resolved payload', idx))
  r[[field]] <- as.character(countries)
  spec <- .op_set_resolved(spec, r)
  spec <- .s232_drop_gate_cache(spec)  # Codex F1 (exemptions don't move gates; recompute is a harmless no-op)
  specs[[auth]] <- spec
  specs
}

#' add_program — add a NEW-COVERAGE tariff (no Chapter-99 backing) to an authority
#' (default `other`, the additive catch-all). The Phase-8 new-coverage verb.
#'
#' `op$program` is a record: `list(id, rate = list(flat = <number>), product_scope,
#' country_scope)`. The calc's no-Ch99 seeder (src/new_coverage.R) applies the flat
#' rate to rate_other on the resolved scope just before stacking. product_scope
#' supports {include='all'} / {prefixes=} / {list=}; country_scope is {include,exclude}.
op_add_program <- function(specs, op, idx) {
  auth <- op$authority %||% 'other'
  if (is.null(specs[[auth]])) {
    stop(sprintf('operation[%s] (add_program): unknown authority "%s" (have: %s)',
                 idx, auth, paste(names(specs), collapse = ', ')))
  }
  prog <- op$program %||% stop(sprintf('operation[%s] (add_program): missing `program` record', idx))
  id <- prog$id %||% stop(sprintf('operation[%s] (add_program): program needs an `id`', idx))
  flat <- prog$rate$flat
  if (is.null(flat) || !is.numeric(flat) || length(flat) != 1L || is.na(flat)) {
    stop(sprintf('operation[%s] (add_program): program "%s" needs rate = list(flat = <number>)', idx, id))
  }
  existing_ids <- vapply(specs[[auth]]$programs, function(p) p$id %||% NA_character_, character(1))
  if (id %in% existing_ids) {
    stop(sprintf('operation[%s] (add_program): program id "%s" already exists in %s', idx, id, auth))
  }
  newp <- authority_program(
    id            = id,
    product_scope = prog$product_scope %||% list(include = 'all'),
    country_scope = prog$country_scope %||% list(include = 'all'),
    rate          = list(flat = flat)
  )
  specs[[auth]]$programs <- c(specs[[auth]]$programs, list(newp))
  specs
}
