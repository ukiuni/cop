#!/usr/bin/env bash
# version 1.1.0
# This file is part of the Copilot CLI helper and is licensed under the MIT License.
# See the accompanying LICENSE.md file for the full text.

set -euo pipefail

COPILOT_CLI_COMMAND="${COPILOT_CLI_COMMAND:-copilot}"
COPILOT_INSTALL_COMMAND="${COPILOT_INSTALL_COMMAND:-npm install -g @github/copilot}"

HISTORY_DIR="${HOME}/.cop/history"
mkdir -p "${HISTORY_DIR}"

# Filter out the Copilot CLI usage summary block to keep the output clean.
filter_usage_summary() {
  awk '
    BEGIN { skip = 0 }
    /^Total usage est:/ { skip = 1; next }
    skip {
      if (/^$/) { skip = 0; next }
      if (/^Total / || /^Usage by model:/ || /^[[:space:]]{2,}/) { next }
      skip = 0
    }
    { print }
  '
}

list_history_files() {
  shopt -s nullglob
  local files=("${HISTORY_DIR}"/*-history.md)
  shopt -u nullglob

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No history entries available."
    return
  fi

  # Sort files by modification time (newest first) using stat and sort
  local count=0
  local file
  for file in "${files[@]}"; do
    printf '%s\t%s\n' "$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file" 2>/dev/null)" "$file"
  done | sort -rn | head -n 10 | while IFS=$'\t' read -r mtime filepath; do
    printf '%s\n' "${filepath#${HISTORY_DIR}/}"
  done
}

get_latest_history_file() {
  shopt -s nullglob
  local files=("${HISTORY_DIR}"/*-history.md)
  shopt -u nullglob

  if [[ ${#files[@]} -eq 0 ]]; then
    return 1
  fi

  ls -1t "${files[@]}" | head -n 1
}

latest_history_flag=false
history_file_arg=""
history_list_only=false
declare -a user_args=()
parsing_options=true

while [[ $# -gt 0 ]]; do
  if [[ "$parsing_options" == true ]]; then
    case "$1" in
      -history-list)
        history_list_only=true
        shift
        continue
        ;;
      -h)
        latest_history_flag=true
        shift
        continue
        ;;
      -hf)
        if [[ $# -lt 2 ]]; then
          echo "Error: -hf requires a file path." >&2
          exit 1
        fi
        history_file_arg="$2"
        shift 2
        continue
        ;;
      --)
        parsing_options=false
        shift
        continue
        ;;
      -*)
        parsing_options=false
        ;;
      *)
        parsing_options=false
        ;;
    esac
  fi

  user_args+=("$1")
  shift
done

if [[ "$history_list_only" == true ]]; then
  list_history_files
  exit 0
fi

if [[ ${#user_args[@]} -eq 0 ]]; then
  echo "Error: Please provide a prompt for Copilot." >&2
  exit 1
fi

prompt="${user_args[*]}"

history_file_to_include=""

if [[ -n "$history_file_arg" ]]; then
  if [[ ! -f "$history_file_arg" ]]; then
    echo "Error: History file '$history_file_arg' does not exist." >&2
    exit 1
  fi
  history_file_to_include="$history_file_arg"
elif [[ "$latest_history_flag" == true ]]; then
  if history_file_to_include="$(get_latest_history_file)" && [[ -n "$history_file_to_include" ]]; then
    :
  else
    echo "Warning: No previous history entries found." >&2
    history_file_to_include=""
  fi
fi

if [[ -n "$history_file_to_include" ]]; then
  history_content="$(<"$history_file_to_include")"
  if [[ -n "$history_content" ]]; then
    printf -v prompt '%s\n\n[Previous Work History (%s)]\n%s' \
      "$prompt" \
      "$(basename "$history_file_to_include")" \
      "$history_content"
  fi
fi

current_datetime="$(date +"%Y%m%d-%H%M%S")"
history_output_file="${HISTORY_DIR}/${current_datetime}-history.md"

history_instruction=$(cat <<EOF
[History Logging Directive]
You MUST always add a detailed worklog of what you just did. Follow these rules without exception:
1. Immediately after finishing the user request, summarize the exact actions you performed, key decisions, and any remaining follow-up tasks.
2. Save that summary in valid Markdown to ${history_output_file}. Overwrite the file if it already exists.
3. Use the following template exactly:

  ## Summary
  - ...

  ## Decisions
  - ...

  ## Next steps
  - ...

4. If anything prevents writing the file, clearly state the reason in your response and stop.
Failure to produce this history file is unacceptable - treat it as the final required step of the task.
EOF
)

prompt=$(printf '%s\n\n%s\n' "$prompt" "$history_instruction")

# Ensure the Copilot CLI is available; install globally if missing.
if ! command -v "${COPILOT_CLI_COMMAND}" >/dev/null 2>&1; then
  eval "${COPILOT_INSTALL_COMMAND}"
fi

if ! command -v "${COPILOT_CLI_COMMAND}" >/dev/null 2>&1; then
  echo "Error: ${COPILOT_CLI_COMMAND} command is unavailable even after attempting installation." >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set." >&2
  exit 1
fi

COPILOT_ALLOW_ALL_TASKS=1 GITHUB_TOKEN="${GITHUB_TOKEN}" "${COPILOT_CLI_COMMAND}" --allow-all-tools --allow-all-paths -p "$prompt" 2>&1 | filter_usage_summary
