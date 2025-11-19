#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COPILOT_SH="${REPO_ROOT}/copilot.sh"
EXISTING_BINARY="$(command -v printf)"
MOCK_CLI_TEMPLATE="${SCRIPT_DIR}/mock-cli"
INSTALL_SH_TEMPLATE="${SCRIPT_DIR}/install-should-not-run.sh"

TMP_DIRS=()
cleanup() {
  local dir
  for dir in "${TMP_DIRS[@]:-}"; do
    if [[ -n "$dir" && -d "$dir" ]]; then
      rm -rf "$dir"
    fi
  done
}
trap cleanup EXIT

run_case() {
  local name="$1"
  shift
  if "$@"; then
    printf '[PASS] %s\n' "$name"
  else
    printf '[FAIL] %s\n' "$name"
    return 1
  fi
}

create_mock_cli() {
  local destination="$1"
  cp "$MOCK_CLI_TEMPLATE" "$destination"
  chmod +x "$destination"
}

create_temp_home() {
  local tmpdir="$(mktemp -d)"
  TMP_DIRS+=("$tmpdir")
  local home="$tmpdir/home"
  mkdir -p "$home"
  printf '%s
' "$home"
}

create_history_file() {
  local home="$1"
  local filename="$2"
  local content="$3"
  local timestamp="${4:-}"
  local history_dir="$home/.cop/history"
  mkdir -p "$history_dir"
  local path="$history_dir/$filename"
  printf '%s' "$content" >"$path"
  if [[ -n "$timestamp" ]]; then
    touch -t "$timestamp" "$path"
  fi
  echo "$path"
}

test_custom_cli_command() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"

  local mock_cli="$tmpdir/mock-cli"
  create_mock_cli "$mock_cli"

  local args_file="$tmpdir/mock-args"
  local install_script="$tmpdir/install-should-not-run.sh"
  cp "$INSTALL_SH_TEMPLATE" "$install_script"
  chmod +x "$install_script"

  local run_log="$tmpdir/run.log"
  if HOME="$home" \
     GITHUB_TOKEN="test-token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$mock_cli" \
     COPILOT_INSTALL_COMMAND="$install_script" \
     "$COPILOT_SH" "Write integration tests" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q "mock CLI output" "$run_log"
  grep -q -- "--allow-all-paths" "$args_file"
}

test_install_command_executes() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"

  local cli_path="$tmpdir/generated-cli"
  local args_file="$tmpdir/generated-args"
  local install_marker="$tmpdir/install-marker"
  local install_script="$tmpdir/install.sh"
  cat >"$install_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cli_path="$1"
marker_path="$2"
cat >"$cli_path" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
: "${MOCK_ARGS_FILE:?MOCK_ARGS_FILE is required}"
printf '%s\n' "$@" >"${MOCK_ARGS_FILE}"
echo "installed mock CLI output"
SCRIPT
chmod +x "$cli_path"
echo "installed" >"$marker_path"
EOF
  chmod +x "$install_script"

  local install_command="\"$install_script\" \"$cli_path\" \"$install_marker\""
  local run_log="$tmpdir/run.log"
  if HOME="$home" \
     GITHUB_TOKEN="test-token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$cli_path" \
     COPILOT_INSTALL_COMMAND="$install_command" \
     "$COPILOT_SH" "Refactor module" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  [[ -f "$install_marker" ]]
  grep -q "installed mock CLI output" "$run_log"
  grep -q -- "--allow-all-tools" "$args_file"
}

test_missing_prompt_errors() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     COPILOT_CLI_COMMAND="$EXISTING_BINARY" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" >"$run_log" 2>&1; then
    echo "expected failure when prompt missing" >&2
    return 1
  fi

  grep -q "Please provide a prompt" "$run_log"
}

test_history_file_flag_requires_argument() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     COPILOT_CLI_COMMAND="$EXISTING_BINARY" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -hf >"$run_log" 2>&1; then
    echo "-hf should fail without a path" >&2
    return 1
  fi

  grep -q "requires a file path" "$run_log"
}

test_history_file_must_exist() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local run_log="$tmpdir/run.log"
  local missing="$tmpdir/missing-history.md"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     COPILOT_CLI_COMMAND="$EXISTING_BINARY" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -hf "$missing" "Prompt" >"$run_log" 2>&1; then
    echo "-hf should fail when file is missing" >&2
    return 1
  fi

  grep -q "does not exist" "$run_log"
}

test_history_list_without_entries() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local run_log="$tmpdir/run.log"

  local output
  if output=$(HOME="$home" \
             COPILOT_CLI_COMMAND="$EXISTING_BINARY" \
             COPILOT_INSTALL_COMMAND=":" \
             "$COPILOT_SH" -history-list 2>"$run_log"); then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q "No history entries available" <<<"$output"
}

test_history_list_with_entries() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local history_dir="$home/.cop/history"
  mkdir -p "$history_dir"
  local file_old="20240101-000001-history.md"
  local file_new="20250202-000002-history.md"
  printf 'old' >"$history_dir/$file_old"
  printf 'new' >"$history_dir/$file_new"
  touch -t 202401010000 "$history_dir/$file_old"
  touch -t 202502020000 "$history_dir/$file_new"

  local run_log="$tmpdir/run.log"
  local output
  if output=$(HOME="$home" \
             COPILOT_CLI_COMMAND="$EXISTING_BINARY" \
             COPILOT_INSTALL_COMMAND=":" \
             "$COPILOT_SH" -history-list 2>"$run_log"); then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q "$file_old" <<<"$output"
  grep -q "$file_new" <<<"$output"
}

test_missing_github_token_errors() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     COPILOT_CLI_COMMAND="$EXISTING_BINARY" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" "Need help" >"$run_log" 2>&1; then
    echo "missing token should fail" >&2
    return 1
  fi

  grep -q "GITHUB_TOKEN environment variable" "$run_log"
}

test_install_failure_reports_error() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local run_log="$tmpdir/run.log"
  local cli_path="$tmpdir/cli-not-present"
  local install_script="$tmpdir/install-fail.sh"
  cat >"$install_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "install attempted but CLI still missing" >&2
EOF
  chmod +x "$install_script"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     COPILOT_CLI_COMMAND="$cli_path" \
     COPILOT_INSTALL_COMMAND="$install_script" \
     "$COPILOT_SH" "Check error" >"$run_log" 2>&1; then
    echo "install failure should surface" >&2
    return 1
  fi

  grep -q "command is unavailable even after attempting installation" "$run_log"
}

test_latest_history_warning_without_files() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local mock_cli="$tmpdir/mock-cli"
  local args_file="$tmpdir/mock-args"
  create_mock_cli "$mock_cli"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$mock_cli" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -h "Continue" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q "Warning: No previous history entries found" "$run_log"
}

test_latest_history_includes_file() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local history_latest
  history_latest=$(create_history_file "$home" "20251212-010101-history.md" "Latest history block" 202512120101)
  local _
  _=$(create_history_file "$home" "20240101-000000-history.md" "Old history block" 202401010000)

  local mock_cli="$tmpdir/mock-cli"
  local args_file="$tmpdir/mock-args"
  create_mock_cli "$mock_cli"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$mock_cli" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -h "Ship it" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q "Latest history block" "$args_file"
  grep -q "$(basename "$history_latest")" "$args_file"
}

test_history_file_argument_empty() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local empty_file
  empty_file=$(create_history_file "$home" "20250303-030303-history.md" "")
  local mock_cli="$tmpdir/mock-cli"
  local args_file="$tmpdir/mock-args"
  create_mock_cli "$mock_cli"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$mock_cli" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -hf "$empty_file" "Outline work" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  if grep -q "Previous Work History" "$args_file"; then
    echo "Empty history file should not be appended" >&2
    return 1
  fi
}

test_history_file_argument_includes_content() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local history_file
  history_file=$(create_history_file "$home" "20250404-040404-history.md" "Detailed history")
  local mock_cli="$tmpdir/mock-cli"
  local args_file="$tmpdir/mock-args"
  create_mock_cli "$mock_cli"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$mock_cli" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -hf "$history_file" "Outline" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q "Detailed history" "$args_file"
  grep -q "$(basename "$history_file")" "$args_file"
}

test_double_dash_allows_literal_dash() {
  local home
  home="$(create_temp_home)"
  local tmpdir="$(dirname "$home")"
  local mock_cli="$tmpdir/mock-cli"
  local args_file="$tmpdir/mock-args"
  create_mock_cli "$mock_cli"
  local run_log="$tmpdir/run.log"

  if HOME="$home" \
     GITHUB_TOKEN="token" \
     MOCK_ARGS_FILE="$args_file" \
     COPILOT_CLI_COMMAND="$mock_cli" \
     COPILOT_INSTALL_COMMAND=":" \
     "$COPILOT_SH" -- -h "literal" >"$run_log" 2>&1; then
    :
  else
    cat "$run_log"
    return 1
  fi

  grep -q -- "-h literal" "$args_file"
  if grep -q "Warning: No previous history entries" "$run_log"; then
    echo "-- should stop option parsing" >&2
    return 1
  fi
}

main() {
  run_case "uses custom CLI command" test_custom_cli_command
  run_case "runs custom install command" test_install_command_executes
  run_case "errors when prompt missing" test_missing_prompt_errors
  run_case "-hf requires operand" test_history_file_flag_requires_argument
  run_case "-hf validates file existence" test_history_file_must_exist
  run_case "history list empty" test_history_list_without_entries
  run_case "history list shows files" test_history_list_with_entries
  run_case "missing token" test_missing_github_token_errors
  run_case "install failure surfaces" test_install_failure_reports_error
  run_case "latest history warns when absent" test_latest_history_warning_without_files
  run_case "latest history includes newest" test_latest_history_includes_file
  run_case "empty history file skipped" test_history_file_argument_empty
  run_case "history file is appended" test_history_file_argument_includes_content
  run_case "double dash stops parsing" test_double_dash_allows_literal_dash
  printf '\nAll tests passed.\n'
}

main "$@"
