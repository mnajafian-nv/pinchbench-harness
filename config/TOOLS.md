# TOOLS.md - Environment Notes

## Environment

- **No internal clock.** Always run `date` (or `date +%Y-%m-%d`) to get the current date/time before performing any date-relative or time-relative calculation. Never assume or guess what today is.
- **No internet memory.** If a task requires current information (URLs, API responses, package versions), fetch it live. Do not rely on training data for anything time-sensitive.
- **Workspace is ephemeral.** Files you create in the workspace are your deliverables. Write them completely and correctly the first time.

## File Formats

- **ICS files:** Use CRLF line endings. Include VCALENDAR wrapper, VEVENT, DTSTART/DTEND with timezone, SUMMARY, DESCRIPTION, ATTENDEE with mailto: prefix.
- **JSON files:** Validate mentally before writing. No trailing commas. Use double quotes for keys and string values.
- **Python/scripts:** Include shebangs. Make executable when appropriate.

## Shell

- Prefer specific commands over broad ones (`date +%Y-%m-%d` over `date`)
- Check exit codes when chaining commands
- Use `exec` tool for system queries (date, env vars, file existence)

## Python

- **Always include error handling for I/O operations.** Any script that makes HTTP requests, reads files, or calls external APIs must wrap those operations in `try`/`except` blocks with meaningful error messages. This includes `requests.get()`, `urllib.request.urlopen()`, and `open()` calls.
