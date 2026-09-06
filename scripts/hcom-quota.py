#!/usr/bin/env python3
# Read account quota headroom for HCOM without exposing credentials or responses.

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
from pathlib import Path


# Accept finite JSON numbers while excluding booleans.
#
# @param  {object}  value
#     Percentage or timestamp read from a usage record.
def is_number(value):
	return type(value) in (int, float) and math.isfinite(value)


# Return the lowest remaining percentage across the available windows.
#
# @param  {list}  windows
#     Used percentages, with null entries for unavailable windows.
def headroom(windows):
	remaining = []  # Percentages from windows the provider actually reported.
	for used in windows:  # Percentage consumed in this window.
		if used is None:
			continue

		if not is_number(used) or not 0 <= used <= 100:
			raise ValueError("Invalid usage percentage")

		remaining.append(100 - used)

	if not remaining:
		raise ValueError("No usage windows available")

	return min(remaining)


# Run a live /usage check under one account and parse its session and week percentages.
#
# @param  {Path|None}  account_home
#     Secondary account's Claude configuration directory, or None for the default
#     account -- setting CLAUDE_CONFIG_DIR even to the default's own path breaks
#     Claude Code's credential resolution, so the default account must inherit
#     the ambient environment unchanged.
def claude_usage(account_home):
	env = (
		os.environ
		if account_home is None
		else dict(os.environ, CLAUDE_CONFIG_DIR=str(account_home))
	)
	try:
		server = subprocess.Popen(  # Isolated group permits cleanup via stop_server.
			["claude", "-p", "/usage"],
			stdin=subprocess.PIPE,
			stdout=subprocess.PIPE,
			stderr=subprocess.DEVNULL,
			env=env,
			start_new_session=True,
		)

		try:
			stdout, _ = server.communicate(
				timeout=20
			)  # Bounded so a stalled probe cannot block the caller.
			if server.returncode != 0:
				raise ValueError("Claude quota request failed")
		finally:
			stop_server(server)
	except (OSError, subprocess.SubprocessError) as error:
		raise ValueError("Claude quota request failed or timed out") from error

	try:
		output = stdout.decode("utf-8")  # Raw /usage report text.
	except UnicodeDecodeError as error:
		raise ValueError("Claude quota response is not valid text") from error

	windows = []  # Percentages parsed from the two required usage lines.
	for label in ("Current session", "Current week (all models)"):
		matches = re.findall(  # Exactly one line per label is expected.
			r"^" + re.escape(label) + r": ([0-9]+(?:\.[0-9]+)?)% used\b",
			output,
			re.MULTILINE,
		)
		if len(matches) != 1:
			raise ValueError("Claude quota response is missing valid usage windows")

		windows.append(float(matches[0]))

	return headroom(windows), time.time() + 180


# Write one request or notification as a JSON line.
#
# @param  {Popen}  server
#     Running Codex app server with an open stdin pipe.
# @param  {dict}  message
#     Request metadata, never account credentials.
def send_rpc(server, message):
	server.stdin.write(json.dumps(message).encode() + b"\n")
	server.stdin.flush()


# Read the matching result within the shared deadline, skipping notifications.
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
			message = json.loads(line)  # Response data stays inside this process.
			if message.get("id") == request_id:
				if "error" in message:
					raise ValueError(f"Codex rejected quota request {request_id}")

				return message["result"]

	raise TimeoutError("Codex quota request timed out")


# Stop the app-server process group and reap its leader without hiding probe errors.
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
		for stream in (
			server.stdin,
			server.stdout,
		):  # Close pipes on success and failure.
			try:
				stream.close()
			except OSError:
				pass


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
		stderr=subprocess.DEVNULL,
		env=environment,
		start_new_session=True,
	)

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
		limits = read_rpc(server, 2, deadline)[
			"rateLimits"
		]  # Current session and weekly limits.
		windows = []  # Only the session and weekly windows influence allocation.
		for name in ("primary", "secondary"):  # The provider can omit either slot.
			window = limits.get(name)  # Null means the slot is unavailable.
			if window is not None and window.get("windowDurationMins") in (
				None,
				300,
				10080,
			):
				windows.append(window.get("usedPercent"))

		return headroom(windows), time.time() + 60
	finally:
		stop_server(server)


# Reuse a numeric quota summary only while its saved expiry is still valid.
#
# @param  {Path}  cache_file
#     Private file for one provider and account.
# @param  {int}  ttl
#     Longest permitted remaining cache lifetime in seconds.
def read_cache(cache_file, ttl):
	try:
		with cache_file.open() as source:  # Summary contains no provider response data.
			cached = json.load(source)  # Previously computed percentage and deadline.

		available = cached["headroom"]  # Remaining percentage saved by this helper.
		expires = cached["expires"]  # Already capped to the Claude source freshness.
		if (
			is_number(available)
			and 0 <= available <= 100
			and is_number(expires)
			and 0 < expires - time.time() <= ttl
		):
			return available
	except (OSError, ValueError, KeyError, TypeError):
		pass

	return None


# Replace the summary atomically so simultaneous team launches read complete JSON.
#
# @param  {Path}  cache_file
#     Destination in the private cache directory.
# @param  {float}  available
#     Validated remaining quota percentage.
# @param  {float}  expires
#     Deadline capped by both the provider TTL and source freshness.
def write_cache(cache_file, available, expires):
	with tempfile.NamedTemporaryFile(
		mode="w", dir=cache_file.parent, delete=False
	) as target:  # Owner-only replacement file.
		try:
			json.dump({"headroom": available, "expires": expires}, target)
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


# Print one cached or fresh headroom percentage for the wrapper's account and TTL.
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
	available = read_cache(cache_file, ttl)  # None requests fresh provider data.
	if available is None:
		home = (
			Path.home()
		)  # Allocation compares known accounts independently of inherited overrides.
		if provider == "claude":
			available, expires = claude_usage(
				None if account == "default" else home / ".claude-2"
			)
		else:
			available, expires = codex_usage(
				home / (".codex" if account == "default" else ".codex-2")
			)

		write_cache(cache_file, available, min(expires, time.time() + ttl))

	print(available)


if __name__ == "__main__":
	signal.signal(signal.SIGTERM, terminate)
	try:
		main()
	except (
		ValueError
	) as error:  # Validation and transport errors contain no provider response data.
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
