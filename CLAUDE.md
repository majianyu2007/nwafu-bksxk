# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **research/documentation archive** for the `bksxk.nwafu.edu.cn` (NWAFU) course-selection system — not an application to run or deploy. It preserves the system's page logic, API endpoints, request/response field shapes, and offline HTML/asset snapshots so research can continue after the live system closes. Most content is written in Chinese; `docs/api.notes.md` is the human-authored field reference and `README.md` is the top-level index.

The eventual consumer is a Go client: the generated contracts (`docs/client.contract.generated.json`, `docs/go-client-catalog.generated.md`) exist to feed Go struct/request-builder/test generation.

## Hard operational constraint

**Never execute write operations against the live system.** Adding courses (`volunteer.do`), dropping (`deleteVolunteer.do`), and textbook order/cancel (`addbook.do`/`modifybook.do`) change real enrollment state. For these, only document fields, call chains, and locally-built mock parameters — do not send requests to obtain responses. This is enforced in tooling: the capture guard blocks write requests, and endpoints flagged `stateChanging` get `executionPolicy: "serialize-only"` (never `read-only-callable`) throughout the generated contracts.

## Commands

```bash
npm install          # installs Playwright (only dependency; needed for capture)
npm test             # syntax-checks every script, then runs ALL *-check validators + sensitive-check
```

`npm test` is the gate. It runs `node --check` on all scripts and then every generator in `--check` mode, which regenerates each artifact in memory and fails if it differs from the committed file.

**Caveat — `npm test` does not pass on a clean checkout.** `endpoint-audit-check` fails ("audit files are stale") unless a capture session's `artifacts/latest/network.jsonl` is present, because the committed `docs/endpoint-inventory.audit.generated.json` embeds runtime request data (its `runtimeRequests` / `runtimeRequestIdentities`) captured on the maintainer's machine. Since the checks are chained with `&&`, this aborts the run before `go-catalog-check` and `sensitive-check` (both of which pass on their own). **Do not "fix" this by running `npm run endpoint-audit` without artifacts — that regenerates the file with zero runtime identities and silently deletes the committed capture evidence.** Every other `*-check` passes offline from committed sources.

Regenerate (write) commands, in dependency order — run after changing any source, then commit the results:

```bash
npm run site-map           # static-snapshot JS  -> docs/site-map.generated.{md,json}
npm run api-manifest       # docs/api.coverage.md -> docs/api.manifest.generated.json
npm run api-requests       # manifest + request-builders.mjs -> docs/api.requests.generated.json
npm run response-schemas   # manifest + runtime + notes -> docs/api.response-schemas.generated.json
npm run page-manifest      # site-map.json -> docs/page.manifest.generated.json
npm run client-contract    # manifest+requests+responses+pages -> docs/client.contract.generated.json
npm run endpoint-audit     # cross-checks all sources -> docs/endpoint-inventory.audit.generated.{md,json}
npm run go-catalog         # client.contract + audit -> docs/go-client-catalog.generated.{md,json}
npm run static-assets      # static-snapshot -> docs/static-assets.manifest.generated.json
npm run offline-snapshots  # artifacts DOM  -> snapshots/*.sanitized.html + manifest
```

Each has a `*-check` sibling (e.g. `npm run api-requests-check`) that verifies without writing; `npm test` chains them all.

Other commands: `npm run summarize` (runtime `network.jsonl` -> `docs/api.generated.md`), `npm run request-examples` (print local param samples; sends nothing), `npm run coverage-check` (site-map ↔ coverage-matrix alignment), `npm run capture` (Playwright capture session, see below), `npm run sanitize` / `npm run sensitive-check` (see Sanitization).

## Architecture: a source → generation → verification pipeline

Two kinds of files live in `docs/`: **hand-maintained sources** and **`*.generated.*` outputs**. Never edit a `*.generated.*` file directly — change its source and rerun its generator, or `npm test` will flag it as stale.

Hand-maintained sources of truth:
- **`docs/api.coverage.md`** — the coverage matrix (`status | method | endpoint | description` tables under `##` sections). This is the *root* input: `generate-api-manifest.mjs` parses these Markdown tables into `api.manifest.generated.json`, deriving each endpoint's `id`, `section`, and `stateChanging` flag. The Chinese status strings are load-bearing — `写操作未执行` (and specific endpoint patterns) mark an endpoint `stateChanging`.
- **`docs/api.notes.md`** — field semantics, call ordering, and frontend source locations, written by hand.
- **`static-snapshot/`** — committed copies of the site's frontend JS/CSS/images. `extract-site-map.mjs` parses the business scripts (`BH_UTILS` + jQuery AJAX calls) into the site map. This is the offline substitute for re-downloading from `xkres.nwafu.edu.cn`.
- **`scripts/request-builders.mjs`** — pure functions that build `querySetting` / `addParam` / `deleteParam` JSON-wrapped params. Feeds `generate-request-examples.mjs`. Sends nothing.

Generation chain (each step reads the prior outputs):

```
api.coverage.md ─► api-manifest ─► api.manifest.generated.json ─┬─► api-requests    ─► api.requests.generated.json
                                                                └─► response-schemas ─► api.response-schemas.generated.json
static-snapshot/ ─► site-map ─► site-map.generated.json ─► page-manifest ─► page.manifest.generated.json

manifest + requests + responses + pages ─► client-contract ─► client.contract.generated.json ─► go-catalog ─► go-client-catalog.generated.*
```

`generate-client-contract.mjs` is also the strict cross-validator: it asserts that `id`/`method`/`endpoint`/`section`/`status`/`stateChanging`/`description` agree across the manifest, requests, responses, and pages, and rejects duplicate ids. `audit-endpoint-inventory.mjs` reconciles five independent views (static-snapshot literal `.do` strings, reconstructed AJAX calls, runtime `network.jsonl`, the coverage matrix, and the client contract) to catch any endpoint recorded in one place but missing from another.

## Runtime capture (optional, local-only)

`npm run capture` launches a headed Playwright Chromium loaded with the guard extension (`extensions/bksxk-guard/`, whose script is copied from `userscripts/bksxk-guard.user.js` by `sync-extension.mjs`). You log in manually; the guard records API calls and **blocks any write request** (matched by method + keyword). Output goes to `artifacts/runs/<stamp>/` with an `artifacts/latest` symlink: `network.jsonl`, `blocked-requests.jsonl`, `snapshot/dom.html`, etc.

`artifacts/` is **git-ignored** — it contains session tokens, cookies, and personal data. Most generators read `artifacts/latest/network.jsonl` only when present (wrapped in try/catch). The exception is `endpoint-audit`: the committed audit JSON embeds the runtime request identities from a real capture, so regenerating it offline drops that evidence (see the `npm test` caveat above). The committed `snapshots/*.sanitized.html` are produced from a captured DOM by `generate-offline-snapshots.mjs`, which strips secrets, disables scripts, and rewrites asset URLs to local `static-snapshot/` paths.

## Sanitization (run before sharing)

Two separate gates:
- **`npm run sanitize`** — cleans the local, git-ignored `artifacts/` logs of sensitive fields.
- **`npm run sensitive-check`** — scans files staged for commit (docs, scripts, snapshots, generated JSON) and blocks real tokens, accounts, captcha values, passwords, and student-id paths. Part of `npm test`.

When adding examples or snapshots, use placeholder values (`<studentCode>`, `<batchCode>`, `<token>`, `<redacted>`) — the request builders and generators already use this convention, and `sensitive-check` enforces it.
