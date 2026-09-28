#!/usr/bin/env bash
# Fake `curl` for exercising scripts/submit.sh without touching the network.
#
# Defined as a shell function and exported (`export -f curl`), so the bash
# process that runs submit.sh resolves `curl` to this function before any
# binary on PATH. No executable file, no chmod, no real HTTP.
#
# Every call appends its arguments (one per line, then a `--END--` line) to
# $CURL_LOG so tests can assert which requests were made and with what data.
#
# Behaviour is driven by environment variables set in the test:
#   STUB_GET_FAIL=1   the cookie GET fails the way `curl -fsS` does on a
#                     network/HTTP error (message on stderr, non-zero exit)
#   STUB_JAR          fixture copied to the `-c` cookie-jar path on the GET
#   STUB_POST_CODE    HTTP status printed for `-w '%{http_code}'` on the POST
#   STUB_POST_BODY    fixture copied to the `-o` response path on the POST

curl() {
  local jar="" out="" write_out="" url=""
  local arg
  {
    for arg in "$@"; do printf '%s\n' "$arg"; done
    printf -- '--END--\n'
  } >>"$CURL_LOG"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -c) jar="$2"; shift 2 ;;
      -o) out="$2"; shift 2 ;;
      -w) write_out="$2"; shift 2 ;;
      -b | -A | -H | --data-urlencode) shift 2 ;;
      -*) shift ;;
      *) url="$1"; shift ;;
    esac
  done

  case "$url" in
    */get_help/*)
      if [[ "${STUB_GET_FAIL:-}" == "1" ]]; then
        echo "curl: (6) Could not resolve host: www.dropbox.com" >&2
        return 6
      fi
      cp "$STUB_JAR" "$jar" || { echo "curl stub: could not copy STUB_JAR '$STUB_JAR'" >&2; return 1; }
      ;;
    */report_abuse/submit)
      cp "$STUB_POST_BODY" "$out" || { echo "curl stub: could not copy STUB_POST_BODY '$STUB_POST_BODY'" >&2; return 1; }
      [[ -n "$write_out" ]] && printf '%s' "$STUB_POST_CODE"
      ;;
    *)
      echo "curl stub: unexpected URL '$url'" >&2
      return 99
      ;;
  esac
  return 0
}
