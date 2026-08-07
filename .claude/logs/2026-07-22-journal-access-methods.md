# Session: 2026-07-22 — Journal article access methods

## Objective
User asked how I can access journal articles on the web that are outside training
data and possibly paywalled. Informational/capability question — no code changes,
no pipeline steps, no plan mode triggered.

## Answer Given (summary)

**Tools available:** `WebSearch` / `WebFetch` (deferred — schemas loaded via
`ToolSearch`), plus `Read` for any PDF already on disk. `WebFetch` sends no
credentials, so publisher-gated content returns an abstract or paywall stub.

**Reliably reachable full text:**
- NBER working papers (`nber.org/papers/wXXXXX`)
- arXiv / SSRN / RePEc / EconPapers preprints
- Author websites + university repositories (highest yield for econ)
- PubMed Central (NIH-funded — relevant to SDWA health-effects lit)
- Unpaywall API (`api.unpaywall.org/v2/<DOI>?email=...`) — locates legal free copies
- Crossref API (`api.crossref.org/works/<DOI>`) — metadata verification, not full text
- Government/agency reports (EPA, USGS, EIA) — fully open

**Out of scope:** Sci-Hub, LibGen, credential sharing, proxy circumvention.

## Design Decisions
| Decision | Rationale |
|----------|-----------|
| Crossref used for citation verification, not retrieval | Confirms author/year/venue/DOI are real — the specific failure mode CoVe targets |
| Abstract-only sources must be flagged explicitly in lit reviews | Paraphrasing a finding seen only in an abstract is the main hallucination vector |
| Recommend user download PDFs to a `lit/` dir via Cornell access | Converts probable citations into verifiable ones; `Read` handles PDFs by page range |

## Connection to Existing Protocol
Reinforces `.claude/rules/post-flight-verification.md` — the `claim-verifier`
CoVe pass exists precisely to catch findings asserted from abstracts or training
memory rather than from paper text. Access limits are the *reason* that protocol
is mandatory for `/lit-review` output.

## Verification Results
- [x] No code executed — informational response only
- [x] No files in `clean_data/`, `raw_data/`, or `output/` touched
- [ ] N/A — no script to run

## Open Questions
- Should I audit the ~25 papers in `reference_literature_review.md` memory to flag
  which have free full text vs. which were sourced from abstracts only? Offered
  to the user; awaiting response.

## Next Steps
- If user accepts: run the free-full-text availability audit over the existing
  literature memory and mark abstract-only entries.
- Otherwise resume prior branch work (`lit-review-cove`).
