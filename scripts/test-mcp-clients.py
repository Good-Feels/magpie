#!/usr/bin/env python3
"""Operate and verify the live Magpie MCP client fixture. See docs/TESTING.md."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import selectors
import shutil
import socket
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLAUDE_CONFIG = Path.home() / "Library/Application Support/Claude/claude_desktop_config.json"
CLIENTS = ("claude", "chatgpt")
CONNECTION_QUERY = "magpie-button-fixture"
CONNECTION_DATA = Path.home() / "Library/Containers/com.goodfeels.magpie.qa/Data"


def fixture_env(directory):
    return dict(os.environ, CFFIXED_USER_HOME=str(directory),
                LLVM_PROFILE_FILE=str(directory / "magpie-%p.profraw"))


def compile_fixture(directory):
    sources = [ROOT / "Magpie/MCP/MCPLocalTransport.swift", ROOT / "Magpie/MCP/MCPProtocol.swift",
               ROOT / "Tests/Fixtures/MCPLiveClientFixture.swift"]
    subprocess.run(["swiftc", "-module-cache-path", str(directory / "modules"),
                    *map(str, sources), "-o", str(directory / "fixture")],
                   check=True, timeout=90)


def prepare_connection_app(directory, scratch):
    directory.mkdir(mode=0o700, exist_ok=False)
    products = scratch / "debug"
    sqlite_module = scratch / "checkouts/GRDB.swift/Sources/GRDBSQLite/module.modulemap"
    libraries = [products / "ClipboardEngine.o", products / "GRDB.o"]
    if not all(path.is_file() for path in [sqlite_module, *libraries]):
        raise SystemExit("Build Magpie in the given scratch directory with the Xcode SwiftPM build system first.")

    app = directory / "Magpie Connection QA.app"
    macos = app / "Contents/MacOS"
    macos.mkdir(parents=True)
    executable = macos / "MagpieConnectionQA"
    sources = [
        "Tests/Fixtures/MCPConnectionFixtureApp.swift",
        "Magpie/Views/MCPSettingsView.swift",
        *[f"Magpie/MCP/{name}.swift" for name in (
            "MCPConnectionSetup", "MCPLocalTransport", "MCPProtocol", "MCPSharing"
        )],
    ]
    subprocess.run([
        "swiftc", "-swift-version", "5", "-Xfrontend", "-disable-sandbox",
        "-module-cache-path", str(directory / "modules"), "-I", str(products),
        "-Xcc", f"-fmodule-map-file={sqlite_module}",
        *[str(ROOT / source) for source in sources], *map(str, libraries),
        "-profile-generate", "-lsqlite3", "-o", str(executable),
    ], check=True, timeout=90)
    info = plistlib.loads((ROOT / "Magpie/Info.plist").read_bytes())
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundlePackageType": "APPL",
        "CFBundleExecutable": executable.name,
        "CFBundleName": "Magpie Connection QA",
        "CFBundleIdentifier": "com.goodfeels.magpie.qa",
        "CFBundleShortVersionString": info["CFBundleShortVersionString"],
    }))
    entitlements = directory / "qa.entitlements"
    entitlements.write_bytes(plistlib.dumps({
        "com.apple.security.app-sandbox": True,
        "com.apple.security.network.client": True,
    }))
    subprocess.run(
        ["codesign", "--force", "--sign", "-", "--entitlements", str(entitlements), str(app)],
        check=True, timeout=20,
    )
    print(f"Open {app}. The search query is {CONNECTION_QUERY}.")


def verify_connection_stdio(directory, phase):
    node = shutil.which("node")
    if not node:
        raise SystemExit("Node.js is required for the desktop launcher transport check.")
    archive = CONNECTION_DATA / "Library/Caches/Magpie/Claude/Magpie.mcpb"
    proof = read_connection_proof(CONNECTION_DATA / "tmp/magpie-fixture-proof.txt")
    executable = directory / "Magpie Connection QA.app/Contents/MacOS/MagpieConnectionQA"
    with tempfile.TemporaryDirectory(dir=directory) as temp, zipfile.ZipFile(archive) as bundle:
        temp = Path(temp)
        config = bundle.read("bridge.json")
        if Path(json.loads(config)["executable"]) != executable:
            raise SystemExit("The cached extension belongs to a different fixture. Click Connect to Claude in this fixture first.")
        (temp / "bridge.json").write_bytes(config)
        (temp / "server.js").write_bytes(bundle.read("server.js"))
        # Some desktop clients expose JS streams separately from OS descriptors 0, 1 and 2.
        (temp / "host.cjs").write_text('''
const fs = require("node:fs");
const fd = Number(process.argv[2]);
Object.defineProperties(process, {
  stdin: { value: fs.createReadStream(null, { fd, autoClose: false }) },
  stdout: { value: fs.createWriteStream(null, { fd, autoClose: false }) },
});
require("./server.js");
''')
        parent, child = socket.socketpair()
        with parent, child, parent.makefile("r", encoding="utf-8") as response:
            parent.settimeout(8)
            with subprocess.Popen([node, str(temp / "host.cjs"), str(child.fileno())],
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  pass_fds=(child.fileno(),)) as process:
                child.close()

                def call(identifier, method, params):
                    message = dict(jsonrpc="2.0", id=identifier, method=method, params=params)
                    parent.sendall((json.dumps(message) + "\n").encode())
                    try:
                        line = response.readline()
                    except TimeoutError:
                        line = ""
                    if not line:
                        raise SystemExit(f"The packaged launcher did not answer {method}.")
                    payload = json.loads(line)
                    if payload.get("id") != identifier or "error" in payload:
                        raise SystemExit(f"The packaged launcher returned an unexpected response to {method}.")
                    return payload["result"]

                try:
                    call(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                           "clientInfo": {"name": "magpie-fixture", "version": "1"}})
                    search = call(2, "tools/call", {"name": "search_shared_clips",
                                                   "arguments": {"query": CONNECTION_QUERY}})
                    clips = json.loads(search["content"][0]["text"])["clips"]
                    if phase == "shared":
                        if len(clips) != 1 or proof in json.dumps(search):
                            raise SystemExit("Search did not return exactly one preview without the proof.")
                        fetched = call(3, "tools/call", {"name": "get_shared_clip",
                                                        "arguments": {"id": clips[0]["id"]}})
                        if proof not in json.dumps(fetched):
                            raise SystemExit("The full clip did not contain the fixture proof.")
                    elif clips:
                        raise SystemExit("The revoked fixture clip was still searchable.")
                    parent.shutdown(socket.SHUT_WR)
                    if process.wait(timeout=8) != 0:
                        raise SystemExit("The packaged launcher exited unsuccessfully after closing its input.")
                finally:
                    if process.poll() is None:
                        process.kill()
    print(f"The packaged launcher passed the {phase} check over the host's separate JavaScript streams.")


def verify_codex(directory, launcher, proof_file):
    node = shutil.which("node")
    if not node or not launcher.is_file():
        raise SystemExit("A Node.js executable and the installed Claude extension launcher are required.")
    proof = read_connection_proof(proof_file)
    config = (
        "mcp_servers.magpie_qa={command=" + json.dumps(node)
        + ",args=[" + json.dumps(str(launcher)) + "],required=true}"
    )
    prompt = (
        "Run this synthetic Magpie connector acceptance check. Use only the magpie_qa MCP tools. "
        "Call search_shared_clips with the exact query magpie-button-fixture. Use the returned ID "
        "to call get_shared_clip. Reply with the Proof line returned by that tool."
    )
    result = subprocess.run([
        "codex", "exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check",
        "--sandbox", "read-only", "--cd", str(directory), "-c", config, "--json", prompt,
    ], capture_output=True, text=True, timeout=120)
    events = []
    for line in result.stdout.splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    items = [event["item"] for event in events if event.get("type") == "item.completed"]
    calls = [item for item in items if item.get("type") == "mcp_tool_call"
             and item.get("server") == "magpie_qa" and item.get("error") is None]
    retrieved = any(item.get("tool") == "get_shared_clip" and proof in json.dumps(item.get("result"))
                    for item in calls)
    answered = any(item.get("type") == "agent_message" and proof in item.get("text", "") for item in items)
    searched = any(item.get("tool") == "search_shared_clips" for item in calls)
    if result.returncode or not (searched and retrieved and answered):
        errors = [event.get("message", "") for event in events if event.get("type") == "error"]
        summary = " ".join(errors).strip()[:400]
        raise SystemExit(f"Codex check failed (search={searched}, fetch={retrieved}, answer={answered}). {summary}")
    print("Codex used the installed Claude extension launcher to search, fetch, and return the exact proof.")


def read_connection_proof(path):
    proof = path.read_text().strip()
    if not re.fullmatch(r"[0-9A-F-]{36}", proof):
        raise SystemExit("The fixture proof line is missing or malformed.")
    return proof


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
    subparsers.add_parser("prepare-connection-app").add_argument("--scratch", type=Path, default=ROOT / ".build")
    subparsers.add_parser("verify-connection-stdio").add_argument("phase", choices=("shared", "revoked"))
    codex = subparsers.add_parser("verify-codex")
    codex.add_argument("--launcher", type=Path, required=True)
    codex.add_argument("--proof-file", type=Path, required=True)
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
    elif args.action == "prepare-connection-app":
        prepare_connection_app(directory, args.scratch.resolve())
    elif args.action == "verify-connection-stdio":
        verify_connection_stdio(directory, args.phase)
    elif args.action == "verify-codex":
        verify_codex(directory, args.launcher.resolve(), args.proof_file.resolve())
    elif args.action.startswith("claude-"):
        claude_config(directory, args.action == "claude-install")
    elif args.action == "revoke":
        (directory / f"{args.client}.revoked").touch()
    else:
        check(directory, args.client, args.phase)


if __name__ == "__main__":
    main()
