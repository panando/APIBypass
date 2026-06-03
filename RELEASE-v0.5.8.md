## v0.5.8 — Terminal launch fixes, upstream 400 fix, reasoning content support

### Fixes

- **iTerm2 cold-start**: AppleScript app name corrected to `"iTerm"` (was `"iTerm2"`), fixing the `-2741` syntax error when iTerm2 is not already running.
- **Terminal window detection**: Uses `CGWindowListCopyWindowInfo` to detect visible windows. If no visible window exists, launches directly without prompting; only shows the "New Tab / New Window / Cancel" dialog when a visible window is present.
- **Upstream 400 error fix**: Strips Anthropic-specific fields (`context_management`, `output_config`) before sending to OpenAI-format upstream. Removes unconditional `enable_thinking: false` that caused upstream rejection.
- **Reasoning content support**: Converts OpenAI `reasoning_content` to Anthropic `thinking` content blocks in both streaming and non-streaming responses, preserving reasoning display in Claude Code terminal for OpenAI-format models.
- **SSE debugging**: Adds upstream error body logging to simplify troubleshooting proxy errors.
