# AGENTS.md

Guidance for coding agents working on this repo.

## What this is

An Alfred 5 workflow that submits reports to Dropbox's public, no-login abuse
form. Two Bash scripts do the work; `info.plist` wires them into Alfred.

```
dropbox-report-abuse <url>  →  Script Filter (filter.sh)  →  Run Script (submit.sh)  →  Notification
```

## The Dropbox endpoint (important, non-obvious)

- Submit URL: `POST https://www.dropbox.com/report_abuse/submit`
- Content type: `application/x-www-form-urlencoded`
- **CSRF: double-submit cookie.** The `t` form field MUST equal the
  `__Host-js_csrf` cookie, or Dropbox returns **HTTP 403** ("something we can't
  verify"). So `submit.sh` first `GET`s a Dropbox page to obtain the cookie,
  then echoes its value back in `t` (and re-sends it as a cookie).
- The GET page used is `https://www.dropbox.com/get_help/abuse/spam-fraud-phishing`,
  which is also the `Referer` on the POST.
- No login, session, or API key is required.

### Form fields

| Field                                   | Source                       | Notes |
| --------------------------------------- | ---------------------------- | ----- |
| `is_xhr`                                | constant `true`              | |
| `t`                                     | `__Host-js_csrf` cookie      | CSRF token, must match cookie |
| `url`                                   | user input (Script Filter)   | the link being reported |
| `explanation`                           | user selection               | `phishing` \| `fraud` \| `abuse` |
| `user_email`                            | workflow config `user_email` | required |
| `user_name`                             | workflow config `user_name`  | optional |
| `abuse_category`                        | constant `2`                 | see below |
| `report_message`                        | constant empty               | free-text field, left blank |
| `harmful_issue_category`                | constant `0`                 | |
| `harmful_content_reporter_relationship` | constant `0`                 | |

**`abuse_category` is held constant at `2`.** It is a separate structured
category from the human-readable `explanation`. The numeric mapping is not
exposed in the form's static HTML (the page is a JS app), so it is not
reverse-engineered here; `2` is the value from a known-good captured request.
The user-facing category selection drives `explanation` only. If you need to
vary `abuse_category`, capture the real values from the live form first. Do
not guess.

## Conventions

- Keep workflow logic in `scripts/*.sh` as plain, testable Bash. Do not inline
  logic into `info.plist`. The plist only calls `./scripts/*.sh "{query}"`.
- After editing any shell script, lint it:
  `shellcheck scripts/*.sh build.sh make_release.sh test/*.bats test/helpers/*.bash`
  (CI runs the same check).
- Run the automated tests after any change to `scripts/submit.sh` or anything
  under `test/`:
  `bats test/` (install with `brew install bats-core`), or without installing
  anything: `npx --yes bats@1 test/`. CI runs them on macOS (`submit.sh` uses
  BSD `mktemp -t`, which GNU `mktemp` rejects).
- The tests never touch the network: `test/helpers/curl_stub.bash` replaces
  `curl` with an exported shell function driven by `STUB_*` variables and
  fixtures in `test/fixtures/`. Every failure-path test carries a
  `# breaks-if:` comment naming the source change it catches.
- In `.bats` files, write `[[ ... ]] || false`, not a bare `[[ ... ]]`: on
  bash < 4.1 (macOS `/bin/bash` is 3.2) a failing `[[ ]]` that is not the
  last line of a test does not fail the test.
- After editing `info.plist`, validate it: `plutil -lint info.plist`.
- After editing `filter.sh`, validate its JSON:
  `./scripts/filter.sh "https://x?a&b" | python3 -m json.tool`.
- Test `submit.sh` without filing a real report using `DRY_RUN=1` (it still
  performs the real token-fetching GET, but skips the POST).
- **Do not file real abuse reports while testing.** A live POST with a valid
  token creates a real report. Use `DRY_RUN=1`, or the known-403 path (a
  deliberately wrong `t`), to exercise the request.
- Repackage with `./build.sh` after any change to shipped files.
- Cut a release with `bash make_release.sh x.y.z`. It bumps `info.plist`'s
  version, builds the versioned `.alfredworkflow` + checksum in `dist/`, and
  prints the commit/push/`gh release create` commands to run manually. It never
  commits, tags, or publishes on its own.

## Files

- `scripts/filter.sh` is the Alfred Script Filter and emits the three category
  items.
- `scripts/submit.sh` performs the GET-token-then-POST report request.
- `info.plist` is the Alfred workflow definition (objects, connections, config).
- `build.sh` zips the workflow into `dist/*.alfredworkflow`.
- `make_release.sh` bumps the version, builds the versioned artifact +
  checksum, and prints the release commands to run manually.
- `test/submit.bats` holds bats-core tests for `submit.sh` (input guards, cookie
  GET failure, CSRF extraction, response classification, `DRY_RUN`).
- `test/helpers/curl_stub.bash` is a network-free `curl` replacement for tests.
- `test/fixtures/` holds cookie-jar and response-body fixtures.
