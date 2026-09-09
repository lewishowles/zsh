#!/usr/bin/env python3
# Read both quota windows per account for HCOM without exposing credentials or responses.

import json
import math
import os
import re
import select
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


# Grammar of a Claude reset phrase, such as "Sep 15 at 6:59am (Europe/London)". The
# minutes are optional because Claude writes "2pm" for a reset falling on the hour.
CLAUDE_RESET_PATTERN = (
	r"(?P<month>[A-Z][a-z]{2}) (?P<day>\d{1,2}) at "
	r"(?P<hour>\d{1,2})(?::(?P<minute>\d{2}))?(?P<period>[ap]m) "
	r"\((?P<timezone>[^)]+)\)"
)

# Longest response or stderr excerpt carried in a probe error, chosen to stay well
# inside the single stderr banner the zsh caller prints.
PROBE_EXCERPT_LIMIT = 320

# Appended to an excerpt that was cut short, so a truncated response is not mistaken
# for the whole of what the tool returned.
PROBE_EXCERPT_MARKER = "..."


# A Codex failure that carries the offending line with it.
#
# read_rpc sees the raw line but not the stderr needed to build the full diagnostic,
# so it raises this and codex_usage assembles the error once the server has stopped.
class QuotaResponseError(ValueError):
	# @param  {str}  message
	#     What went wrong, used as the error text.
	# @param  {str}  response
	#     The line that could not be used, already decoded.
	def __init__(self, message, response):
		super().__init__(message)

		# The unusable line, read by codex_usage when it builds the probe error.
		self.response = response


# Reduce text to a single bounded line for inclusion in an error.
#
# Collapsing whitespace keeps the diagnostic on one line, and the length cap keeps a
# long report or session transcript out of the error entirely.
#
# @param  {str}  text
#     Response or stderr text to shorten.
def excerpt(text):
	collapsed = " ".join(text.split())

	if not collapsed:
		return "<empty>"

	if len(collapsed) <= PROBE_EXCERPT_LIMIT:
		return collapsed

	return (
		collapsed[: PROBE_EXCERPT_LIMIT - len(PROBE_EXCERPT_MARKER)]
		+ PROBE_EXCERPT_MARKER
	)


# Read process output as text, tolerating bytes that are not valid UTF-8.
#
# A probe fails for reasons that can themselves corrupt its output, so undecodable
# bytes are replaced rather than raising and hiding the original failure.
#
# @param  {object}  value
#     Bytes, string, or None captured from a probe.
def decode_text(value):
	if isinstance(value, bytes):
		return value.decode("utf-8", errors="replace")

	if value is None:
		return ""

	return str(value)


# Render a Codex response as text an excerpt can be taken from.
#
# @param  {object}  response
#     Parsed response data, or the text of a line that could not be parsed.
def response_text(response):
	if isinstance(response, str):
		return response

	try:
		return json.dumps(response, separators=(",", ":"))
	except (TypeError, ValueError):
		return str(response)


# Build the error a failed probe raises, naming what the tool actually returned.
#
# Without the excerpts, a logged-out account, an empty response, and a genuine change
# in wording all report the same sentence and cannot be told apart afterwards.
#
# @param  {str}  message
#     What went wrong.
# @param  {object}  response
#     The response being parsed when it failed.
# @param  {str}  stderr
#     Anything the tool wrote to stderr.
def probe_error(message, response, stderr):
	return ValueError(
		f"{message}; response: {excerpt(response)}; stderr: {excerpt(stderr)}"
	)


# Accept finite JSON numbers while excluding booleans.
#
# @param  {object}  value
#     Percentage, reset timestamp, or window length read from a usage record.
def is_number(value):
	return type(value) in (int, float) and math.isfinite(value)


# Convert one Claude reset phrase into a Unix timestamp.
#
# Claude states the day and time but never the year, so the current year is tried
# first and then the next, taking the first that is not already past. A date the
# candidate year does not hold, such as Feb 29, is skipped rather than raising.
#
# @param  {str}  reset_text
#     Reset phrase from a /usage line, such as "Sep 15 at 6:59am (Europe/London)".
def claude_reset_epoch(reset_text):
	match = re.fullmatch(CLAUDE_RESET_PATTERN, reset_text)
	if match is None:
		raise ValueError("Claude quota reset is invalid")

	month = match.group("month")
	day = match.group("day")
	hour = match.group("hour")
	minute = match.group("minute") or "00"
	period = match.group("period")
	timezone_name = match.group("timezone")
	try:
		timezone = ZoneInfo(timezone_name)
		current = datetime.now(timezone)
		for year in (current.year, current.year + 1):
			try:
				reset = datetime.strptime(
					f"{month} {day} {year} {hour}:{minute}{period}",
					"%b %d %Y %I:%M%p",
				).replace(tzinfo=timezone)
			except ValueError:
				continue
			if reset >= current:
				return int(reset.timestamp())
	except (ValueError, ZoneInfoNotFoundError) as error:
		raise ValueError("Claude quota reset is invalid") from error

	raise ValueError("Claude quota reset is invalid")


# Run a live /usage check under one account and report both of its quota windows.
#
# Returns six values, session before week: remaining percentage, reset timestamp, and
# window length in seconds.
#
# @param  {Path|None}  account_home
#     Secondary account's Claude configuration directory, or None for the default
#     account. The default account is probed with CLAUDE_CONFIG_DIR removed rather
#     than set: an agent pane exports the secondary account's path, which would
#     otherwise measure that account instead, and pointing the variable at the
#     default's own path breaks Claude Code's credential resolution.
def claude_usage(account_home):
	if account_home is None:
		env = dict(os.environ)
		env.pop("CLAUDE_CONFIG_DIR", None)
	else:
		env = dict(os.environ, CLAUDE_CONFIG_DIR=str(account_home))

	try:
		server = subprocess.Popen(  # Isolated group permits cleanup via stop_server.
			["claude", "-p", "/usage"],
			stdin=subprocess.PIPE,
			stdout=subprocess.PIPE,
			stderr=subprocess.PIPE,
			env=env,
			start_new_session=True,
		)

		try:
			stdout, stderr = server.communicate(
				timeout=20
			)  # Bounded so a stalled probe cannot block the caller.
			stderr_text = decode_text(stderr)  # Kept for the error if parsing fails.
			output = stdout.decode("utf-8")  # Raw /usage report text.

			if server.returncode != 0:
				raise probe_error("Claude quota request failed", output, stderr_text)
		except UnicodeDecodeError as error:
			raise probe_error(
				"Claude quota response is not valid text",
				decode_text(stdout),
				stderr_text,
			) from error
		finally:
			stop_server(server)
	except (OSError, subprocess.SubprocessError) as error:
		raise ValueError("Claude quota request failed or timed out") from error

	quota = []  # Remaining percentage, reset epoch and window length, session then week.

	# Claude never reports how long its windows run, so the two lengths are stated here.
	# Codex reports its own and is read rather than hardcoded.
	for label, window_seconds in (
		("Current session", 300 * 60),
		("Current week (all models)", 10080 * 60),
	):
		matches = list(
			re.finditer(
				r"^"
				+ re.escape(label)
				+ r": ([0-9]+(?:\.[0-9]+)?)% used\b(?:.*?resets "
				+ r"(?P<reset>"
				+ CLAUDE_RESET_PATTERN
				+ r"))?$",
				output,
				re.MULTILINE,
			)
		)
		if len(matches) != 1:
			raise probe_error(
				"Claude quota response is missing valid usage windows",
				output,
				stderr_text,
			)

		used = float(matches[0].group(1))
		if not 0 <= used <= 100:
			raise probe_error("Invalid usage percentage", output, stderr_text)

		reset_text = matches[0].group("reset")  # Reset timestamp, or None when the window has not started.

		# Claude leaves the reset clause off a window the user has not opened
		# yet, so it only ever goes missing at zero usage. Any other line
		# without one is a response shape we cannot score.
		if reset_text is None:
			if used != 0:
				raise probe_error(
					"Claude quota response is missing valid usage windows",
					output,
					stderr_text,
				)

			# An unopened window has its whole length still ahead of it.
			reset = time.time() + window_seconds
		else:
			try:
				reset = claude_reset_epoch(reset_text)
			except ValueError as error:
				raise probe_error(str(error), output, stderr_text) from error

		quota.extend((100 - used, reset, window_seconds))

	return quota, time.time() + 180


# Write one request or notification as a JSON line.
#
# @param  {Popen}  server
#     Running Codex app server with an open stdin pipe.
# @param  {dict}  message
#     Request metadata, never account credentials.
def send_rpc(server, message):
	server.stdin.write(json.dumps(message).encode() + b"\n")
	server.stdin.flush()


# Read the matching result within the shared deadline.
#
# Notifications are skipped, and a line that is not a JSON object is reported with the
# line itself so a malformed reply can be identified afterwards.
#
# @param  {Popen}  server
#     Running Codex app server with an open stdout pipe.
# @param  {int}  request_id
#     ID of the outstanding request.
# @param  {float}  deadline
#     Monotonic time when the whole probe must stop.
def read_rpc(server, request_id, deadline):
	pending = b""  # Incomplete JSON line from the current request.
	total_bytes = 0  # Limit unsolicited output as well as elapsed time.
	while time.monotonic() < deadline:
		if not select.select(
			[server.stdout], [], [], max(0, deadline - time.monotonic())
		)[0]:
			raise TimeoutError("Codex quota request timed out")

		block = os.read(
			server.stdout.fileno(), 65536
		)  # Available bytes without a blocking readline.
		if not block:
			raise ValueError(f"Codex closed the connection during request {request_id}")

		total_bytes += len(block)
		if total_bytes > 1048576:
			raise ValueError("Codex exceeded the quota response size limit")

		pending += block
		while b"\n" in pending:
			line, pending = pending.split(
				b"\n", 1
			)  # Complete message and remaining bytes.
			line_text = decode_text(line)
			try:
				message = json.loads(line)  # Response data stays inside this process.
			except ValueError as error:
				raise QuotaResponseError("Codex returned invalid JSON", line_text) from error

			if not isinstance(message, dict):
				raise QuotaResponseError("Codex returned an invalid response", line_text)

			if message.get("id") == request_id:
				if "error" in message:
					raise QuotaResponseError(
						f"Codex rejected quota request {request_id}", line_text
					)

				return message["result"]

	raise TimeoutError("Codex quota request timed out")


# Stop the app-server process group and reap its leader without hiding probe errors.
#
# Returns whatever the child wrote to stderr, for the Codex caller to include in its
# diagnostic. The Claude caller has already drained the pipe through communicate.
#
# @param  {Popen}  server
#     Child started in its own session so other Codex processes are unaffected.
def stop_server(server):
	try:
		os.killpg(server.pid, signal.SIGKILL)
	except (PermissionError, ProcessLookupError):
		# A denied group signal must still allow a direct-child cleanup attempt.
		try:
			server.kill()
		except (PermissionError, ProcessLookupError):
			pass

	try:
		server.wait(timeout=1)
	except (OSError, subprocess.TimeoutExpired):
		print(
			"Quota probe cleanup could not confirm the child exited",
			file=sys.stderr,
		)
	finally:
		stderr = b""
		if server.stderr is not None and server.poll() is not None:
			try:
				stderr = server.stderr.read1(4096)
			except (OSError, ValueError):
				pass

		for stream in (
			server.stdin,
			server.stdout,
			server.stderr,
		):  # Close pipes on success and failure.
			if stream is not None:
				try:
					stream.close()
				except OSError:
					pass

	return stderr


# Initialise Codex, read rate limits, and always stop the temporary server.
#
# @param  {Path}  account_home
#     Selected account's Codex configuration directory.
def codex_usage(account_home):
	environment = dict(
		os.environ, CODEX_HOME=str(account_home)
	)  # Override inherited account selection.
	server = subprocess.Popen(  # Isolated group permits cleanup of descendants too.
		["codex", "app-server"],
		stdin=subprocess.PIPE,
		stdout=subprocess.PIPE,
		stderr=subprocess.PIPE,
		env=environment,
		start_new_session=True,
	)

	failure = None  # Held until stop_server has run and stderr can be read.
	response = ""  # Stands in when the failure happened before any response arrived.

	try:
		deadline = time.monotonic() + 8  # One deadline for both RPC responses.
		send_rpc(
			server,
			{
				"method": "initialize",
				"id": 1,
				"params": {
					"clientInfo": {
						"name": "hcom_quota",
						"title": "HCOM quota",
						"version": "1.0.0",
					},
					"capabilities": {"experimentalApi": False},
				},
			},
		)
		read_rpc(server, 1, deadline)
		send_rpc(server, {"method": "initialized"})
		send_rpc(server, {"method": "account/rateLimits/read", "id": 2})
		limits_response = read_rpc(server, 2, deadline)
		response = response_text(limits_response)
		limits = limits_response[
			"rateLimits"
		]  # Current session and weekly limits.
		quota = []  # Remaining percentage, reset epoch and window length, session then week.

		# Codex names its windows by slot rather than by length, so each slot's stated
		# duration is checked against the window it is being read as.
		for name, expected_duration in (("primary", 300), ("secondary", 10080)):
			window = limits.get(name)
			if not isinstance(window, dict):
				raise ValueError("Codex quota response is missing valid usage windows")

			used = window.get("usedPercent")  # Percentage consumed in this window.
			reset = window.get("resetsAt")  # Unix timestamp when the window refills.
			duration = window.get("windowDurationMins")  # Slot identity, checked below.
			if (
				not is_number(used)
				or not 0 <= used <= 100
				or not is_number(reset)
				or reset < 0
				or duration != expected_duration
			):
				raise ValueError("Invalid Codex quota window")

			quota.extend((100 - used, reset, duration * 60))

		return quota, time.time() + 60
	except (AttributeError, KeyError, OSError, TypeError, ValueError) as error:
		failure = error
	finally:
		stderr = decode_text(stop_server(server))

	if failure is not None:
		response = response_text(getattr(failure, "response", response))
		# A KeyError renders as the bare quoted key, so name the type for anything that
		# did not arrive as a stated ValueError message.
		detail = str(failure) or "Codex quota response is unusable"
		message = (
			detail
			if isinstance(failure, ValueError)
			else f"{type(failure).__name__}: {detail}"
		)
		raise probe_error(message, response, stderr) from failure


# Reuse a saved quota summary only while its expiry is still valid.
#
# A summary written before this layout has no quota entry, so it fails the same way as
# any unreadable file and a fresh probe runs instead.
#
# @param  {Path}  cache_file
#     Private file for one provider and account.
# @param  {int}  ttl
#     Longest permitted remaining cache lifetime in seconds.
def read_cache(cache_file, ttl):
	try:
		with cache_file.open() as source:  # Summary contains no provider response data.
			cached = json.load(source)  # Previously computed quota and deadline.

			quota = cached["quota"]
			expires = cached["expires"]  # Already capped to the Claude source freshness.
			valid_quota = type(quota) is list and len(quota) == 6  # Both windows present.
			if valid_quota:
				for remaining, reset, duration in (quota[:3], quota[3:]):
					if (
						not is_number(remaining)
						or not 0 <= remaining <= 100
						or not is_number(reset)
						or reset < 0
						or not is_number(duration)
						or duration <= 0
					):
						valid_quota = False
						break

			if (
				valid_quota
				and is_number(expires)
				and 0 < expires - time.time() <= ttl
			):
				return quota
	except (OSError, ValueError, KeyError, TypeError):
		pass

	return None


# Replace the summary atomically so simultaneous team launches read complete JSON.
#
# @param  {Path}  cache_file
#     Destination in the private cache directory.
# @param  {list}  quota
#     Validated six-value window summary.
# @param  {float}  expires
#     Deadline capped by both the provider TTL and source freshness.
def write_cache(cache_file, quota, expires):
	with tempfile.NamedTemporaryFile(
		mode="w", dir=cache_file.parent, delete=False
	) as target:  # Owner-only replacement file.
		try:
			json.dump({"quota": quota, "expires": expires}, target)
			target.close()
			os.replace(target.name, cache_file)
		finally:
			if os.path.exists(target.name):
				os.unlink(target.name)


# Unwind probe cleanup when a caller terminates this helper.
#
# @param  {int}  signum
#     Signal received from the caller.
# @param  {frame}  frame
#     Interrupted frame, unused.
def terminate(signum, frame):
	raise SystemExit(128 + signum)


# Print the cached or freshly probed session and weekly quota figures for the wrapper's account and TTL.
def main():
	if len(sys.argv) != 4:
		raise ValueError("Expected provider, account and cache TTL")

	# provider: quota source, "claude" or "codex".
	# account: account identifier, "default" or "2".
	# ttl_text: cache lifetime in seconds, still a string until validated below.
	provider, account, ttl_text = sys.argv[1:]
	if provider not in ("claude", "codex") or account not in ("default", "2"):
		raise ValueError("Unknown provider or account")

	ttl = int(ttl_text)  # Cache policy chosen by the wrapper.
	if not 0 <= ttl <= (60 if provider == "codex" else 180):
		raise ValueError("Invalid quota cache lifetime")

	cache_dir = Path(tempfile.gettempdir()) / (
		"hcom-quota-" + str(os.getuid())
	)  # Shared across shell processes.
	cache_dir.mkdir(mode=0o700, exist_ok=True)
	metadata = (
		cache_dir.lstat()
	)  # Reject another user's directory or an unsafe shared cache.
	if (
		cache_dir.is_symlink()
		or metadata.st_uid != os.getuid()
		or metadata.st_mode & 0o077
	):
		raise ValueError("Unsafe quota cache directory")

	cache_file = cache_dir / (
		provider + "-" + account + ".json"
	)  # Provider/account cache key.
	quota = read_cache(cache_file, ttl)  # None requests fresh provider data.
	if quota is None:
		home = (
			Path.home()
		)  # Allocation compares known accounts independently of inherited overrides.
		if provider == "claude":
			quota, expires = claude_usage(
				None if account == "default" else home / ".claude-2"
			)
		else:
			quota, expires = codex_usage(
				home / (".codex" if account == "default" else ".codex-2")
			)

		write_cache(cache_file, quota, min(expires, time.time() + ttl))

	print(*quota)


if __name__ == "__main__":
	signal.signal(signal.SIGTERM, terminate)
	try:
		main()
	except (
		ValueError
	) as error:  # Carries a bounded excerpt of the response and stderr, never credentials.
		print(str(error), file=sys.stderr)
		sys.exit(1)
	except (
		OSError,
		KeyError,
		TypeError,
		AttributeError,
		subprocess.SubprocessError,
	) as error:  # Report error type without private file contents.
		print(f"Quota probe failed: {type(error).__name__}", file=sys.stderr)
		sys.exit(1)
