# Dropbox Abuse Report — Alfred Workflow

Report Dropbox spam, fraud, and phishing links straight from Alfred — no login,
no API key.

It drives Dropbox's public abuse form at
`https://www.dropbox.com/report_abuse/submit`.

## Install

1. Download `Dropbox-Abuse-Report.alfredworkflow` (from Releases, or run
   `./build.sh` to package it into `dist/`).
2. Double-click it to import into Alfred (requires the Alfred Powerpack).
3. Open the workflow's **Configuration** and set:
   - **Your email** (required) — sent as the reporter email.
   - **Your name** (optional) — sent as the reporter name.

## Usage

```
report-abuse <dropbox-link>
```

1. Trigger Alfred and type `report-abuse` followed by the Dropbox link.
2. Pick a category: **phishing**, **fraud**, or **abuse**.
3. Press <kbd>Enter</kbd>. A notification confirms whether Dropbox accepted the
   report.

## How it works

Dropbox's report endpoint uses a double-submit-cookie CSRF check: the `t` form
field must match the `__Host-js_csrf` cookie. The workflow:

1. `GET`s `https://www.dropbox.com/get_help/abuse/spam-fraud-phishing` to obtain
   the `__Host-js_csrf` cookie.
2. `POST`s the report to `/report_abuse/submit`, echoing that cookie value back
   in both the `t` field and the request cookies.

See [`AGENTS.md`](AGENTS.md) for the full request/response details and the
fields that are held constant.

## Development

- Workflow logic lives in `scripts/filter.sh` (Alfred Script Filter) and
  `scripts/submit.sh` (the reporting request). Both are plain Bash and testable
  from the command line.
- `info.plist` wires them together: Script Filter → Run Script → Notification.
- `./build.sh` repackages the `.alfredworkflow`.

Test the submit path without actually filing a report:

```bash
DRY_RUN=1 explanation=phishing user_email=you@example.com \
  ./scripts/submit.sh "https://www.dropbox.com/scl/fi/…"
```

## License

MIT — see [`LICENSE`](LICENSE).
