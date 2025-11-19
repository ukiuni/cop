# Copilot CLI helper

This workspace provides `copilot.sh`, a guard script around the `copilot` CLI that ensures the tool is installed, forwards prompts, and injects the required environment variables.

## Prerequisites

- Node.js/npm available on your PATH (needed for installing `@github/copilot`).
- `GITHUB_TOKEN` exported with a token that Copilot CLI accepts.
	- Create a fresh GitHub token by visiting https://github.com/settings/profile, then navigating to **Developer Settings → Personal access tokens → Fine-grained tokens → Generate new token**. Grant every permission whose name includes "Copilot" (or the closest match) and finally `export GITHUB_TOKEN=<your-token>` in your shell profile so the script can read it.

## Usage

After copying or moving `copilot.sh` into your desired directory, grant it execute permission:

```bash
chmod +x copilot.sh
```

When you're ready, run it like this:

```bash
./copilot.sh "Summarize the latest git commit"
```

The script will:

1. Install `@github/copilot` globally if the `copilot` command is missing.
2. Require `GITHUB_TOKEN` to be set and pass it to the CLI invocation.
3. Pass all script arguments as a single prompt via the `-p` flag.
4. Enable every Copilot CLI task by exporting `COPILOT_ALLOW_ALL_TASKS=1` and using `--allow-all-tools` and `--allow-all-paths`.
5. Instruct Copilot to record the current session's work history in `~/.cop/history/{timestamp}-history.md` so future runs can reference it.

## Work history helpers

Every invocation injects a directive asking Copilot to save a Markdown work log under `~/.cop/history/`. You can leverage those logs when launching a new session:

- `./copilot.sh -h "Continue improving the deployment script"` &mdash; include the most recent history file in the new prompt so Copilot can pick up where it left off.
- `./copilot.sh -hf 20250119-091530-history.md "Ship the release"` &mdash; include a specific log file in the prompt.
- `./copilot.sh -history-list` &mdash; list up to ten most recent history filenames without invoking Copilot (useful for picking the right `-hf` target).

History files live under `~/.cop/history`. The script prints the path that Copilot should write for the current run; you can open that file afterwards to review or edit the log.

> ℹ️ Place any `-h`, `-hf`, or `-history-list` flags before your actual prompt. Once you begin writing the prompt (or pass `--`), the script stops parsing options so you can freely mention those strings in the conversation itself.

## Alias setup

To invoke the helper with a short `cop` command, add an alias that points to the absolute path of `copilot.sh`:

```bash
echo "alias cop='$(realpath copilot.sh)'" >> ~/.zprofile
source ~/.zprofile
```

Alternatively, replace `$(realpath copilot.sh)` with `/Users/tito/asdfasdf/copilot.sh` (or whatever absolute path applies on your machine) if you prefer to hard-code it.

## Troubleshooting

- To debug without executing Copilot, you can run `bash -n copilot.sh` to perform a syntax check.
- Ensure global npm installs are allowed (you may need `sudo` depending on your setup).

## License

This project is released under the [MIT License](LICENSE.md).
