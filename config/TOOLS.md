# TOOLS.md - Environment Notes

## Environment

- **No internal clock.** Always run `date` (or `date +%Y-%m-%d`) to get the current date/time before performing any date-relative or time-relative calculation. Never assume or guess what today is.
- **No internet memory.** If a task requires current information (URLs, API responses, package versions), fetch it live. Do not rely on training data for anything time-sensitive.
- **Workspace is ephemeral.** Files you create in the workspace are your deliverables. Write them completely and correctly the first time.

## Writing Large Files

For files **longer than 100 lines** (test suites, long scripts, reports), create them with `exec` using a heredoc instead of the `write` tool. This avoids truncation issues with large payloads:

```
exec: cat > my_file.py << 'PYEOF'
... content ...
PYEOF
```

If the `write` tool fails or the file appears empty/truncated, **immediately retry with `exec` + heredoc**.

## Date and Time

- **Always compute relative dates programmatically.** Never guess "next Tuesday" or "last Friday". Run:
  ```
  python3 -c "from datetime import date, timedelta; today=date.today(); diff=(1-today.weekday())%7 or 7; print(today+timedelta(days=diff))"
  ```
  Adjust the weekday number (0=Mon, 1=Tue, ..., 6=Sun) as needed.
- For ICS `DTSTART`/`DTEND`, use the computed date in `YYYYMMDDTHHMMSS` format.

## File Formats

- **ICS files:** Use CRLF line endings (`\r\n`). Include VCALENDAR wrapper, VEVENT, DTSTART/DTEND with timezone, SUMMARY, DESCRIPTION, ATTENDEE with `mailto:` prefix.
- **JSON files:** Validate mentally before writing. No trailing commas. Use double quotes for keys and string values.
- **Python/scripts:** Include shebangs. Make executable when appropriate.

## Debugging Config Files

When fixing bugs in configuration files (CI/CD pipelines, Dockerfiles, K8s manifests):

1. Address **every** symptom listed in the task — do not stop at the first fix.
2. After fixing, **search for security issues**: redundant credential exposure (a secret referenced inline AND exposed as an env var is a leak — remove the env block), hardcoded tokens, overly broad permissions.
3. Re-read the entire file after editing to verify no old/broken patterns remain.

## Research and Web Tasks

- **Use APIs directly** when endpoints are known. For example, Polymarket trending markets: `https://gamma-api.polymarket.com/markets?active=true&order=volumeNum&ascending=false&limit=10`
- **Be time-efficient.** Focus on the specific metric or data point requested. Do not over-research. If a task asks for one number, find that number and stop.
- **Never fabricate data.** If an API is unreachable, note the failure and try an alternative (web search, cached data). Do not invent numbers or markets.

## Image Generation

- Use the built-in `image_generate` tool when available. Craft a detailed prompt covering all key elements mentioned in the task.
- If `image_generate` is not available, use `exec` to call an image generation API (e.g., `curl` to pollinations.ai, fal.ai, or another provider) and save the output file.
- Always verify the output file exists and is non-empty after generation.

## Shell

- Prefer specific commands over broad ones (`date +%Y-%m-%d` over `date`)
- Check exit codes when chaining commands
- Use `exec` tool for system queries (date, env vars, file existence)

## Python

- **Always include error handling for I/O operations.** Any script that makes HTTP requests, reads files, or calls external APIs must wrap those operations in `try`/`except` blocks with meaningful error messages. This includes `requests.get()`, `urllib.request.urlopen()`, and `open()` calls.
