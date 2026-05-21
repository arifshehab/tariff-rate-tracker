# Enabling Zenodo (deferred)

Zenodo is a free archive run by CERN that mints a permanent DOI per GitHub
release. We've **chosen not to set it up yet** — the GitHub citation surface
(`CITATION.cff` + the "Cite this repository" widget) is enough for now.

This note records how to turn it on if a downstream consumer needs a
citable DOI, or we decide research-paper visibility is worth it.

## When to bother

Turn Zenodo on if:

- A consumer cites the tracker in an academic paper and needs a DOI in
  the references list.
- We want the project surfaced in Google Scholar / OpenAIRE / DataCite
  search.
- We start publishing dated releases and want each one to have a fixed
  reproducibility anchor.

Skip Zenodo if releases stay rare and the audience is mostly
informal/policy-adjacent — `CITATION.cff` already gives them a copy-pasteable
citation through the GitHub widget.

## What it gives us

- **Concept DOI** (`10.5281/zenodo.XXXXXXX`) — "all versions" reference;
  always resolves to the latest release. This is what we'd put in
  `CITATION.cff` and the README.
- **Per-release DOI** — one DOI per dated release tag. Used when a
  downstream consumer wants to cite a specific snapshot of the data.

Both are free and permanent (Zenodo's pitch is "as long as CERN exists").
DOIs cannot be unminted, so think before publishing test releases.

## Setup (one-time, ~10 min)

Needs Budget-Lab-Yale GitHub org admin access.

1. Go to <https://zenodo.org/>, click "Log in" → "GitHub" → authorize.
2. Navigate to <https://zenodo.org/account/settings/github/>. You'll see
   a list of every repo your GitHub identity has admin access to.
3. Find `Budget-Lab-Yale/tariff-rate-tracker`. Flip the toggle ON.
   (If the repo doesn't appear, the org admin needs to grant Zenodo
   access to the org's repos under GitHub org settings → Applications.)
4. Publish a GitHub release on the repo (any tag). Within ~5 min Zenodo
   creates a record and emails the DOI.
5. **Edit the Zenodo record** to set authors, keywords, license. The
   form auto-populates from `CITATION.cff` if present, but Zenodo's
   own form is the source of truth on the Zenodo side.
6. Copy the **concept DOI** (not the version DOI). Uncomment the
   `identifiers:` block in `CITATION.cff` and paste it:
   ```yaml
   identifiers:
     - type: doi
       value: "10.5281/zenodo.XXXXXXX"
       description: "All-versions concept DOI"
   ```
7. Add a "Cited via" line in `README.md` near the existing "Citing this
   work" section pointing at the DOI.

## After setup

Every subsequent GitHub release automatically triggers a new Zenodo
deposit + version DOI. No per-release action needed.

If we ever set up the weekly auto-release workflow (Phase 3 of the
data-feed scope), keep the cadence at weekly or less frequent —
Zenodo's terms of service ask depositors not to fire daily/hourly.

## Trade-offs

- **Cannot delete a release on Zenodo's side.** A release can be marked
  obsolete or restricted, but the DOI stays minted. Be deliberate with
  what gets published.
- **Bandwidth.** Zenodo is an archive, not a CDN. For high-traffic
  "give me the latest data" use cases, point consumers at the GitHub
  release URL; the Zenodo DOI is the citation/permanence layer behind
  it.
- **Org vs personal.** Make sure the toggle is enabled under the
  Budget-Lab-Yale org account, not a personal one. The DOI metadata
  follows whoever clicked "publish" on Zenodo's side, which matters
  for attribution.

## Authority pointer

Zenodo's own GitHub-integration docs:
<https://help.zenodo.org/docs/profile/linking-github/>
