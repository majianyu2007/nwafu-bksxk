# Offline Snapshots

This directory contains sanitized, commit-safe page snapshots for studying the
course-selection UI after the live system is closed.

- `grablessons.sanitized.html` is generated from `artifacts/latest/snapshot/dom.html`.
- `index.sanitized.html` is generated from a public login/index HTML capture when
  `BKSXK_LOGIN_HTML` or `/tmp/bksxk-index.html` is available, then kept as a
  commit-safe offline snapshot.
- External JS execution is disabled by changing executable scripts to
  `type="text/plain"`.
- Public CSS, JS, and image references point to `../static-snapshot/`.
- Session tokens, login fields, student identifiers, course numbers, and
  teaching-class identifiers are redacted.

Regenerate with:

```bash
npm run offline-snapshots
```

Check without requiring the ignored `artifacts/` source:

```bash
npm run offline-snapshots-check
```
