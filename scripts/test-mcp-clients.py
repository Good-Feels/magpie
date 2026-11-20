#!/usr/bin/env python3
"""Operate and verify the live Magpie MCP client fixture. See docs/TESTING.md."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import selectors
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CLAUDE_CONFIG = Path.home() / "Library/Application Support/Claude/claude_desktop_config.json"
CLIENTS = ("claude", "chatgpt")


def fixture_env(directory):
    return dict(os.environ, CFFIXED_USER_HOME=str(directory),
                LLVM_PROFILE_FILE=str(directory / "magpie-%p.profraw"))


def compile_fixture(directory):
    sources = [ROOT / "Magpie/MCP/MCPLocalTransport.swift", ROOT / "Magpie/MCP/MCPProtocol.swift",
               ROOT / "Tests/Fixtures/MCPLiveClientFixture.swift"]
    subprocess.run(["swiftc", "-module-cache-path", str(directory / "modules"),
                    *map(str, sources), "-o", str(directory / "fixture")],
                   check=True, timeout=90)


def run_fixture(directory, bridge):
    directory.mkdir(mode=0o700, exist_ok=False)
    if not bridge.is_file():
        raise SystemExit("Build Magpie first and pass the executable with --bridge.")
    (directory / "manifest.json").write_text(json.dumps({
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "runner_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "fixture_sha256": hashlib.sha256((ROOT / "Tests/Fixtures/MCPLiveClientFixture.swift").read_bytes()).hexdigest(),
        "bridge_sha256": hashlib.sha256(bridge.read_bytes()).hexdigest(),
        "environment": platform.platform(),
        "bridge": str(bridge),
    }, indent=2) + "\n")
    compile_fixture(directory)
    with subprocess.Popen([directory / "fixture"], cwd=directory, env=fixture_env(directory),
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as process:
        ready = selectors.DefaultSelector()
        ready.register(process.stdout, selectors.EVENT_READ)
        try:
            if not ready.select(timeout=10) or process.stdout.readline().strip() != "Magpie fixture ready":
                raise SystemExit("Timed out waiting for the isolated MCP listener.")
            print(f"Ready at {directory}", flush=True)
            for client in CLIENTS:
                print(f"{client}: magpie-{client}-{directory.name}", flush=True)
            if process.wait(timeout=1800) != 0:
                raise SystemExit("The isolated MCP fixture exited unexpectedly.")
        finally:
            ready.close()
            process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)


def claude_config(directory, install):
    manifest = json.loads((directory / "manifest.json").read_text())
    name = f"magpie-qa-{directory.name}"
    block = directory / "claude-config-insertion"
    raw = CLAUDE_CONFIG.read_text()
    data = json.loads(raw)
    servers = data["mcpServers"]
    if install:
        if name in servers or block.exists():
            raise SystemExit("This fixture already has a Claude Desktop entry.")
        entry = {
            "command": manifest["bridge"],
            "args": ["--mcp-stdio"],
            "env": {"CFFIXED_USER_HOME": str(directory),
                    "LLVM_PROFILE_FILE": str(directory / "magpie-%p.profraw")},
        }
        location = re.search(r'"mcpServers"\s*:\s*\{', raw)
        if not location:
            raise SystemExit("Could not locate the top-level mcpServers object.")
        # Insert only our entry so existing config remains byte-for-byte intact.
        insertion = "\n    " + json.dumps(name) + ": " + json.dumps(entry) + ("," if servers else "")
        offset = location.end()
        updated = raw[:offset] + insertion + raw[offset:]
        servers[name] = entry
        if json.loads(updated) != data:
            raise SystemExit("The insertion would alter unrelated Claude Desktop configuration.")
        block.write_text(insertion)
    else:
        if name not in servers:
            print("Temporary Claude Desktop entry is already absent.")
            return
        insertion = block.read_text()
        if raw.count(insertion) == 1:
            updated = raw.replace(insertion, "", 1)
            del servers[name]
            if json.loads(updated) != data:
                raise SystemExit("The removal would alter unrelated Claude Desktop configuration.")
        else:
            saved_entry = json.loads("{" + insertion.rstrip(",") + "}")[name]
            if servers[name] != saved_entry:
                raise SystemExit("Temporary Claude Desktop entry changed during the test.")
            del servers[name]
            updated = json.dumps(data, indent=2) + "\n"
    temp = CLAUDE_CONFIG.with_name(f".{name}.json")
    with os.fdopen(os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as output:
        output.write(updated)
    os.replace(temp, CLAUDE_CONFIG)
    print(f"{'Installed' if install else 'Removed'} temporary Claude Desktop entry {name}.")


def check(directory, client, phase):
    phases = ("shared-search", "shared-fetch") if phase == "shared" else ("revoked-empty-search",)
    expected = [name for name in phases if not (directory / f"{client}.{name}").exists()]
    if expected:
        raise SystemExit(f"{client}: missing observed tool replies: {', '.join(expected)}")
    print(f"{client}: passed {', '.join(phases)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="private, unique fixture path under /private/tmp")
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("serve").add_argument("--bridge", type=Path, required=True)
    subparsers.add_parser("claude-install")
    subparsers.add_parser("claude-remove")
    subparsers.add_parser("revoke").add_argument("client", choices=CLIENTS)
    checker = subparsers.add_parser("check")
    checker.add_argument("client", choices=CLIENTS)
    checker.add_argument("phase", choices=("shared", "revoked"))
    args = parser.parse_args()
    directory = args.directory.resolve()
    if directory.parent != Path("/private/tmp") or not re.fullmatch(r"magpie-[a-z0-9-]+", directory.name):
        parser.error("use /private/tmp/magpie-<short-unique-suffix>")
    if args.action == "serve":
        run_fixture(directory, args.bridge.resolve())
    elif args.action.startswith("claude-"):
        claude_config(directory, args.action == "claude-install")
    elif args.action == "revoke":
        (directory / f"{args.client}.revoked").touch()
    else:
        check(directory, args.client, args.phase)


if __name__ == "__main__":
    main()
