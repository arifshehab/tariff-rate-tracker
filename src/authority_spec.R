# =============================================================================
# authority_spec.R — the AuthoritySpec datatype
# =============================================================================
#
# One uniform per-authority parameter structure (docs/authority_spec.md). The
# baseline parser/adapter PRODUCES these; the scenario layer MUTATES them; the
# calculator READS them. "Baseline = the empty scenario" — same structure, no
# operations applied.
#
# Representation: a plain named list with an S3 class tag (NOT S4/R6). The whole
# pipeline is base-list + tidyverse, policy_params is a nested list, and specs
# must serialize cleanly to per-revision RDS and across future workers — an S3
# list does all of that; S4/R6 would be foreign and serialize poorly.
#
# This file defines ONLY the datatype + validation. Operations (the scenario
# delta) and the JSON->spec adapter live elsewhere (Phase 2 / Phase 1 adapter).
#
# Shape (one authority):
#   authority_spec(
#     authority       = 'section_232',
#     stacking        = list(class = 'primary_metal', exceptions = list()),
#     usmca_treatment = 'per_program' | 'exempt' | 'eligible' | 'none',
#     active          = list(from = as.Date('2025-03-12'), until = NA),
#     programs        = list(authority_program(...), ...)
#   )
# A "spec set" is a named list of authority_spec objects, one per authority,
# class 'authority_spec_set'.
# =============================================================================

# Allowed vocabularies (normalized labels introduced by the schema; NOT live
# code symbols — the calculator's case_when branches are mapped onto these).
STACKING_CLASSES   <- c('primary_metal', 'primary_full', 'content_split', 'additive')
USMCA_TREATMENTS    <- c('exempt', 'eligible', 'none', 'per_program')
METAL_TYPES         <- c('steel', 'aluminum', 'copper', 'other', 'none')

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- constructors -----------------------------------------------------------

#' Construct one program within an authority.
#'
#' @param id            character — unique within the authority
#' @param product_scope list — one of {chapters, products_file, prefixes_file,
#'   prefixes, list_file} (a precedence, resolved by the adapter), plus optional
#'   exclude_file. Stored as-is.
#' @param country_scope list — {include: 'all' | <census codes>, exclude: <codes/file>}
#' @param rate          list — {default, by_country, overrides, target_total,
#'   by_product_tier, product_overrides_file, ...} (distinct mechanisms; see doc)
#' @param metal         list|NULL — 232 only: {type, content}. Omit for non-metal.
#' @param active        list|NULL — {from, until}; NULL inherits the authority's.
#' @param stacking      list|NULL — per-program override of the authority stacking.
authority_program <- function(id, product_scope = list(), country_scope = list(include = 'all'),
                              rate = list(), metal = NULL, active = NULL, stacking = NULL) {
  structure(
    list(id = id, product_scope = product_scope, country_scope = country_scope,
         rate = rate, metal = metal, active = active, stacking = stacking),
    class = 'authority_program'
  )
}

#' Construct one authority's spec.
#'
#' @param authority       character — e.g. 'section_232', 'section_301',
#'   'ieepa_reciprocal', 'ieepa_fentanyl', 'section_122', 'section_201',
#'   'mfn', 'other'
#' @param stacking        list — {class, exceptions}; default class for programs
#' @param usmca_treatment character — see USMCA_TREATMENTS
#' @param active          list — {from, until}; until = first inactive day (exclusive)
#' @param programs        list of authority_program objects
authority_spec <- function(authority,
                           stacking = list(class = 'additive', exceptions = list()),
                           usmca_treatment = 'none',
                           active = list(from = NA, until = NA),
                           programs = list()) {
  structure(
    list(authority = authority, stacking = stacking,
         usmca_treatment = usmca_treatment, active = active, programs = programs),
    class = 'authority_spec'
  )
}

#' Bundle per-authority specs into a set (named by authority).
authority_spec_set <- function(...) {
  specs <- list(...)
  if (length(specs) == 1L && is.null(names(specs)) && is.list(specs[[1]]) &&
      !inherits(specs[[1]], 'authority_spec')) {
    specs <- specs[[1]]   # allow passing a pre-built named list
  }
  nm <- vapply(specs, function(s) s$authority %||% NA_character_, character(1))
  existing <- names(specs)
  if (is.null(existing)) existing <- rep('', length(specs))
  names(specs) <- ifelse(is.na(existing) | existing == '', nm, existing)
  structure(specs, class = 'authority_spec_set')
}

# ---- predicates -------------------------------------------------------------

is_authority_spec      <- function(x) inherits(x, 'authority_spec')
is_authority_program   <- function(x) inherits(x, 'authority_program')
is_authority_spec_set  <- function(x) inherits(x, 'authority_spec_set')

# ---- validation (fail loud; decision 5 / doc operations rules) --------------

#' Validate a single authority spec. Stops on the first structural violation.
validate_authority_spec <- function(spec) {
  if (!is_authority_spec(spec)) stop('not an authority_spec: ', spec$authority %||% '<?>')
  a <- spec$authority

  sc <- spec$stacking$class %||% NA_character_
  if (!is.na(sc) && !sc %in% STACKING_CLASSES) {
    stop(sprintf('[%s] invalid stacking.class: %s (allowed: %s)',
                 a, sc, paste(STACKING_CLASSES, collapse = ', ')))
  }
  if (!is.null(spec$usmca_treatment) && !spec$usmca_treatment %in% USMCA_TREATMENTS) {
    stop(sprintf('[%s] invalid usmca_treatment: %s', a, spec$usmca_treatment))
  }

  for (p in spec$programs) {
    if (!is_authority_program(p)) stop(sprintf('[%s] program is not an authority_program', a))
    # Resolve the program's effective stacking class (own override or authority default)
    pcls <- (p$stacking$class %||% spec$stacking$class) %||% NA_character_
    if (!is.na(pcls) && !pcls %in% STACKING_CLASSES) {
      stop(sprintf('[%s/%s] invalid stacking.class: %s', a, p$id, pcls))
    }
    # primary_metal REQUIRES a real metal.type (doc decision: hard error otherwise)
    if (identical(pcls, 'primary_metal')) {
      mt <- p$metal$type %||% NA_character_
      if (is.na(mt) || identical(mt, 'none')) {
        stop(sprintf('[%s/%s] stacking.class=primary_metal requires metal.type (got %s)',
                     a, p$id, mt))
      }
    }
    if (!is.null(p$metal) && !is.null(p$metal$type) && !p$metal$type %in% METAL_TYPES) {
      stop(sprintf('[%s/%s] invalid metal.type: %s', a, p$id, p$metal$type))
    }
  }
  invisible(TRUE)
}

#' Validate a whole spec set. Also checks program-id uniqueness within authority.
validate_spec_set <- function(specs) {
  if (!is_authority_spec_set(specs) && !is.list(specs)) stop('not a spec set')
  for (spec in specs) {
    validate_authority_spec(spec)
    ids <- vapply(spec$programs, function(p) p$id %||% NA_character_, character(1))
    dup <- ids[duplicated(ids)]
    if (length(dup)) stop(sprintf('[%s] duplicate program id(s): %s',
                                  spec$authority, paste(unique(dup), collapse = ', ')))
  }
  invisible(TRUE)
}

# ---- printing ---------------------------------------------------------------

print.authority_spec <- function(x, ...) {
  cat(sprintf('<authority_spec> %s | stacking=%s | usmca=%s | %d program(s)\n',
              x$authority, x$stacking$class %||% '?', x$usmca_treatment %||% '?',
              length(x$programs)))
  for (p in x$programs) {
    cls <- (p$stacking$class %||% x$stacking$class) %||% '?'
    cat(sprintf('   - %-18s scope=%s rate=%s stacking=%s%s\n',
                p$id,
                if (identical(p$country_scope$include, 'all')) 'all-countries'
                  else paste0(length(p$country_scope$include %||% list()), ' countries'),
                paste(names(p$rate), collapse = ','),
                cls,
                if (!is.null(p$metal$type)) paste0(' metal=', p$metal$type) else ''))
  }
  invisible(x)
}

print.authority_spec_set <- function(x, ...) {
  cat(sprintf('<authority_spec_set> %d authorities: %s\n',
              length(x), paste(names(x), collapse = ', ')))
  for (s in x) print(s)
  invisible(x)
}
