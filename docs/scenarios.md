# Scenarios and Counterfactuals

> **The legacy YAML scenario engine was removed in Phase 7.** `config/scenarios.yaml`,
> `src/apply_scenarios.R`, and `run_post_build_scenarios_per_revision` are gone.
> Counterfactuals are no longer post-build *patches* of the output panel — they are
> **AuthoritySpec operations** applied to the policy spec *before* the calculator
> runs, so every downstream column (stacking, daily series, ETRs) is recomputed
> consistently. "Baseline = the empty scenario."

## How scenarios work now

A scenario is a list of **operations** applied to the baseline `authority_spec_set`
before `calculate_rates_for_revision()`. See
[`docs/authority_spec.md`](authority_spec.md) for the design and
[`src/scenario_ops.R`](../src/scenario_ops.R) for the authoritative verb list and
per-authority support. Current verbs:

| verb | authorities | effect |
|---|---|---|
| `set_country_scope` | section_301, section_201 | replace a program's country scope (e.g. 301 → {China, Vietnam}) |
| `set_active` | any | move a program/authority active window (e.g. the IEEPA invalidation date) |
| `disable` | 301/201 (scope) + 232/s122 (rate) | empty the scope, or zero the resolved rates |
| `set_rate` | section_232 (per program), section_122 | change a rate (232 recomputes `has_232`; s122 sets `has_s122`) |
| `set_exempt` | section_232 (steel/aluminum/autos) | replace a program's country exemption list |

New-coverage verbs (`add_program` for a brand-new tariff with no Chapter-99
backing, plus its import-weight provisioning) land in **Phase 8**.

## Authoring and running a scenario

Operations are a plain list of records; pass them to the build via the
`TARIFF_SCENARIO_OPS` env var (an RDS path), which `scripts/build_revision.R`
reads, or via the `operations` field of a rebuild alt-spec (threaded through
`build_alternative_timeseries()`).

```r
# Bump Section 232 steel to 50% on one revision:
ops <- list(list(op = "set_rate", authority = "section_232",
                 program = "steel", rate = 0.50))
saveRDS(ops, "my_scenario.rds")
```

```bash
TARIFF_SCENARIO_OPS=my_scenario.rds TARIFF_TS_DIR=data/timeseries_steel \
  Rscript scripts/build_revision.R rev_20
```

The empty operations list is the identity (baseline). Operations fail **loudly**
on anything unsupported — they never silently no-op.
