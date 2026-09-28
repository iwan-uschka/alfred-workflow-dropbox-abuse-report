#!/usr/bin/env bats
# Tests for scripts/submit.sh. `curl` is replaced by an exported shell
# function (test/helpers/curl_stub.bash), so no test ever reaches Dropbox or
# files a real report.
#
# Each @test runs in its own subshell, so per-test `export STUB_*=...`
# overrides are meant to stay local to that test.
#
# `[[ ... ]] || false`: on bash < 4.1 (macOS ships 3.2) a failing `[[ ]]`
# that is not the last command of a test does NOT fail the test. The
# `|| false` makes every `[[ ]]` assertion count regardless of position.
# shellcheck disable=SC2030,SC2031

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SUBMIT="$REPO_ROOT/scripts/submit.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"

  # shellcheck source=test/helpers/curl_stub.bash
  source "$BATS_TEST_DIRNAME/helpers/curl_stub.bash"
  export -f curl

  export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
  : >"$CURL_LOG"

  export user_email="tester@example.com"
  export user_name="Tester"
  export explanation="phishing"
  export STUB_JAR="$FIXTURES/jar_with_csrf.txt"
  export STUB_POST_CODE="200"
  export STUB_POST_BODY="$FIXTURES/body_error_false.json"
  unset STUB_GET_FAIL DRY_RUN
}

run_submit() {
  run bash "$SUBMIT" "https://www.dropbox.com/scl/fi/abc/phish.html"
}

post_count() {
  grep -c 'report_abuse/submit' "$CURL_LOG" || true
}

# --- invalid input -----------------------------------------------------------

# breaks-if: submit.sh drops the `-z "$URL"` guard and proceeds without a URL
@test "missing URL: exits 1 and makes no request" {
  run bash "$SUBMIT"
  [ "$status" -eq 1 ]
  [ "$output" = "❌ No URL to report" ]
  [ ! -s "$CURL_LOG" ]
}

# breaks-if: submit.sh drops the `-z "$EMAIL"` guard and submits without a reporter email
@test "missing email: exits 1 and makes no request" {
  unset user_email
  run_submit
  [ "$status" -eq 1 ]
  [ "$output" = "❌ Set your email in the workflow configuration first" ]
  [ ! -s "$CURL_LOG" ]
}

# --- external failure: cookie GET --------------------------------------------

# breaks-if: submit.sh stops checking the exit status of the CSRF-cookie GET (`if ! curl -fsS ...`)
@test "cookie GET fails: reports 'Could not reach Dropbox' and never POSTs" {
  export STUB_GET_FAIL=1
  run_submit
  [ "$status" -eq 1 ]
  [[ "$output" == *"❌ Could not reach Dropbox to start the report"* ]] || false
  [ "$(post_count)" -eq 0 ]
}

# --- CSRF token extraction ---------------------------------------------------

# breaks-if: submit.sh drops the empty-$CSRF check and POSTs with an empty `t` token
@test "cookie jar without __Host-js_csrf: exits 1 and never POSTs" {
  export STUB_JAR="$FIXTURES/jar_without_csrf.txt"
  run_submit
  [ "$status" -eq 1 ]
  [ "$output" = "❌ Dropbox did not issue a CSRF token" ]
  [ "$(post_count)" -eq 0 ]
}

# breaks-if: submit.sh sends a `t` form field or `t` cookie that differs from the __Host-js_csrf cookie value
@test "success: the CSRF cookie value is echoed back as the t field and cookie" {
  run_submit
  [ "$status" -eq 0 ]
  [ "$output" = "✅ Reported to Dropbox as phishing" ]
  [ "$(post_count)" -eq 1 ]
  # form field: `--data-urlencode t=<token>`
  grep -x -A1 -- '--data-urlencode' "$CURL_LOG" | grep -qx 't=TESTTOKEN123abc'
  # double-submit cookie: `-b t=<token>`
  grep -x -A1 -- '-b' "$CURL_LOG" | grep -qx 't=TESTTOKEN123abc'
}

# --- response classification (looks_like_error) ------------------------------

# breaks-if: looks_like_error stops treating `"error": "<string>"` in a 200 body as an error
@test "HTTP 200 with \"error\": \"...\" body is reported as a failure" {
  export STUB_POST_BODY="$FIXTURES/body_error_string.json"
  run_submit
  [ "$status" -eq 1 ]
  [[ "$output" == "❌ Dropbox answered 200 but reported an error: "*'"error": "invalid_request"'* ]] || false
}

# breaks-if: looks_like_error stops matching `"status": "error"` in a 200 body
@test "HTTP 200 with \"status\": \"error\" body is reported as a failure" {
  export STUB_POST_BODY="$FIXTURES/body_status_error.json"
  run_submit
  [ "$status" -eq 1 ]
  [[ "$output" == "❌ Dropbox answered 200 but reported an error: "* ]] || false
}

# breaks-if: looks_like_error matches any `"error"` key, so `"error": false` is misread as a failure
@test "HTTP 200 with \"error\": false body is reported as success" {
  export STUB_POST_BODY="$FIXTURES/body_error_false.json"
  run_submit
  [ "$status" -eq 0 ]
  [ "$output" = "✅ Reported to Dropbox as phishing" ]
}

# breaks-if: looks_like_error stops matching a bare `"error": true` value
@test "HTTP 200 with \"error\": true body is reported as a failure" {
  export STUB_POST_BODY="$FIXTURES/body_error_true.json"
  run_submit
  [ "$status" -eq 1 ]
}

# breaks-if: submit.sh's SNIPPET truncation (`cut -c1-120`) is widened, narrowed, or removed
@test "HTTP 200 error body longer than 120 chars is truncated in the message" {
  export STUB_POST_BODY="$FIXTURES/body_error_long.json"
  run_submit
  [ "$status" -eq 1 ]
  local full_body expected_snippet
  full_body="$(tr -d '\r\n' < "$STUB_POST_BODY")"
  expected_snippet="$(cut -c1-120 <<<"$full_body")"
  [ "${#full_body}" -gt 120 ]
  [[ "$output" == *"$expected_snippet"* ]] || false
  [[ "$output" != *"${full_body:120}"* ]] || false
}

# breaks-if: submit.sh treats any non-error body as success without checking the HTTP code is 200
@test "HTTP 403 (CSRF mismatch) is reported as a rejection with the status code" {
  export STUB_POST_CODE="403"
  export STUB_POST_BODY="$FIXTURES/body_403.html"
  run_submit
  [ "$status" -eq 1 ]
  [ "$output" = "❌ Dropbox rejected the report (HTTP 403)" ]
}

# --- DRY_RUN guard rail ------------------------------------------------------

# breaks-if: submit.sh stops exiting before the POST when DRY_RUN=1, filing a real report
@test "DRY_RUN=1 fetches the token but never POSTs" {
  export DRY_RUN=1
  run_submit
  [ "$status" -eq 0 ]
  [[ "$output" == "DRY_RUN: would report 'https://www.dropbox.com/scl/fi/abc/phish.html' as 'phishing' (token=TESTTO…"* ]] || false
  [ "$(post_count)" -eq 0 ]
}

# --- curl stub sanity ---------------------------------------------------

# breaks-if: the stub's URL-matching (`*/get_help/*`, `*/report_abuse/submit`) stops matching submit.sh's actual request URLs
@test "curl stub: an unrecognized URL fails loudly instead of silently succeeding" {
  run bash -c 'source "'"$BATS_TEST_DIRNAME"'/helpers/curl_stub.bash"; export -f curl; curl https://example.com/unexpected'
  [ "$status" -eq 99 ]
}
