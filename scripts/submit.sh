#!/bin/bash
# Submits an abuse report to Dropbox's public (no-login) endpoint.
#
# Dropbox protects the endpoint with a double-submit-cookie CSRF check: the
# `t` form field must equal the `__Host-js_csrf` cookie. So we first GET a
# Dropbox page to obtain that cookie, then POST the report echoing the cookie
# value back in `t`.
#
# Inputs:
#   $1                 the URL to report (from the actioned Script Filter item)
#   $explanation       report category: phishing | fraud | abuse  (workflow var)
#   $user_email        reporter email    (workflow configuration)
#   $user_name         reporter name     (workflow configuration)
#   $DRY_RUN=1         build the request but do not actually POST (for testing)
#
# Prints a single status line, which the workflow surfaces as a notification.
set -uo pipefail

URL="${1:-}"
EXPLANATION="${explanation:-abuse}"
EMAIL="${user_email:-}"
NAME="${user_name:-}"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
FORM_PAGE="https://www.dropbox.com/get_help/abuse/spam-fraud-phishing"
SUBMIT_URL="https://www.dropbox.com/report_abuse/submit"

if [[ -z "$URL" ]]; then
  echo "❌ No URL to report"
  exit 1
fi
if [[ -z "$EMAIL" ]]; then
  echo "❌ Set your email in the workflow configuration first"
  exit 1
fi

JAR="$(mktemp -t dbxabuse)"
RESP="$(mktemp -t dbxabuse_resp)"
trap 'rm -f "$JAR" "$RESP"' EXIT

# 1. Obtain the CSRF cookie.
if ! curl -fsS -c "$JAR" -A "$UA" "$FORM_PAGE" -o /dev/null; then
  echo "❌ Could not reach Dropbox to start the report"
  exit 1
fi

CSRF="$(awk '/__Host-js_csrf/{print $NF}' "$JAR")"
if [[ -z "$CSRF" ]]; then
  echo "❌ Dropbox did not issue a CSRF token"
  exit 1
fi

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "DRY_RUN: would report '$URL' as '$EXPLANATION' (token=${CSRF:0:6}…, email=$EMAIL)"
  exit 0
fi

# XHR endpoints can answer HTTP 200 yet carry an error in the JSON body. We
# have no captured success body to compare against (getting one would file a
# real report), so this is a conservative heuristic: flag bodies that
# explicitly declare an error ("error": true/"…"/{…}/1, "status": "error"),
# but stay quiet on "error": false/null/0/"".
looks_like_error() {
  grep -Eqi '"(err|error)"[[:space:]]*:[[:space:]]*(true|"[^"]|\{|[1-9])|"status"[[:space:]]*:[[:space:]]*"(error|fail)' "$1"
}

# 2. POST the report, echoing the CSRF token back in `t` and as a cookie.
CODE="$(curl -sS -o "$RESP" -w '%{http_code}' \
  -b "$JAR" -b "t=$CSRF" -A "$UA" \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H 'Origin: https://www.dropbox.com' \
  -H "Referer: $FORM_PAGE" \
  --data-urlencode 'is_xhr=true' \
  --data-urlencode "t=$CSRF" \
  --data-urlencode 'abuse_category=2' \
  --data-urlencode "url=$URL" \
  --data-urlencode "user_name=$NAME" \
  --data-urlencode "user_email=$EMAIL" \
  --data-urlencode 'report_message=' \
  --data-urlencode "explanation=$EXPLANATION" \
  --data-urlencode 'harmful_issue_category=0' \
  --data-urlencode 'harmful_content_reporter_relationship=0' \
  "$SUBMIT_URL")"

if [[ "$CODE" == "200" ]] && ! looks_like_error "$RESP"; then
  echo "✅ Reported to Dropbox as $EXPLANATION"
else
  SNIPPET="$(tr -d '\r\n' < "$RESP" | cut -c1-120)"
  if [[ "$CODE" == "200" ]]; then
    echo "❌ Dropbox answered 200 but reported an error: $SNIPPET"
  else
    echo "❌ Dropbox rejected the report (HTTP $CODE)"
  fi
  exit 1
fi
