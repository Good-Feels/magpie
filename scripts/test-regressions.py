#!/usr/bin/env python3
"""Run both native suites with pinned dependencies, bounded waits and saved evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output-dir', type=Path, default=ROOT / 'test-results' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
parser.add_argument('--root-scratch', type=Path, default=ROOT / '.build/regression-root')
parser.add_argument('--engine-scratch', type=Path, default=ROOT / '.build/regression-engine')
parser.add_argument('--cache-path', type=Path, default=ROOT / '.build/regression-cache')
parser.add_argument('--timeout', type=int, default=600, help='Maximum seconds per suite, including dependency acquisition')
args = parser.parse_args()
if args.timeout <= 0:
    parser.error('--timeout must be positive')
out = args.output_dir.resolve()
out.mkdir(parents=True, exist_ok=True)
source = {}
for pattern in ['Magpie/**/*.swift', 'ClipboardEngine/Sources/**/*.swift', 'MagpieKeeper*/**/*.swift', 'Tests/**/*.swift', 'ClipboardEngine/Tests/**/*.swift', '**/Package.resolved', '**/Package.swift']:
    for file in sorted(ROOT.glob(pattern)):
        if '.build' not in file.parts:
            source[str(file.relative_to(ROOT))] = hashlib.sha256(file.read_bytes()).hexdigest()
def inspect(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=10)
    return result.stdout.strip() if result.returncode == 0 else None

info = plistlib.loads((ROOT / 'Magpie/Info.plist').read_bytes())
head = inspect(['git', 'rev-parse', 'HEAD'])
summary = {
    'started_at': datetime.now(timezone.utc).isoformat(),
    'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'source_files_sha256': source,
    'info_plist_sha256': hashlib.sha256((ROOT / 'Magpie/Info.plist').read_bytes()).hexdigest(),
    'git_head': head or 'archive/unknown',
    'git_dirty': bool(inspect(['git', 'status', '--porcelain'])) if head else None,
    'environment': {'macos': platform.mac_ver()[0], 'build': inspect(['sw_vers', '-buildVersion']),
                    'swift': inspect(['swift', '--version']), 'architecture': platform.machine()},
    'app_version': info['CFBundleShortVersionString'], 'app_build': info['CFBundleVersion'],
    'suites': [],
}

def stop_group(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    except ProcessLookupError:
        process.wait()

def interrupted(signum, frame):
    raise InterruptedError('Received signal ' + str(signum))

signal.signal(signal.SIGTERM, interrupted)
was_interrupted = False
for name, package, scratch in [('root', ROOT, args.root_scratch), ('engine', ROOT / 'ClipboardEngine', args.engine_scratch)]:
    scratch = scratch.resolve()
    command = ['swift', 'test', '--package-path', str(package), '--disable-sandbox', '--force-resolved-versions', '--enable-code-coverage', '--scratch-path', str(scratch), '--cache-path', str(args.cache_path.resolve()), '--config-path', str(scratch / 'config')]
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(scratch / 'modules'))
    result = {'name': name, 'command': command, 'status': 'running'}
    print('Running ' + name + ' suite', flush=True)
    with (out / (name + '.log')).open('w') as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=args.timeout)
            result.update(exit_code=code, status='passed' if code == 0 else 'failed')
        except subprocess.TimeoutExpired:
            stop_group(process)
            result.update(status='blocked-timeout', exit_code=process.returncode)
        except (KeyboardInterrupt, InterruptedError):
            stop_group(process)
            result.update(status='interrupted', exit_code=process.returncode)
            was_interrupted = True
    # Export only this product's files. Dependency coverage is intentionally omitted.
    coverage = []
    for file in scratch.glob('**/codecov/*.json'):
        try:
            payload = json.loads(file.read_text())
            for data in payload.get('data', []):
                for entry in data.get('files', []):
                    path = entry['filename']
                    if path.startswith(str(ROOT) + '/'):
                        relative = str(Path(path).relative_to(ROOT))
                        if relative.startswith(('Magpie/', 'ClipboardEngine/Sources/', 'MagpieKeeper/', 'MagpieKeeperCore/')):
                            coverage.append({'file': relative, 'summary': entry['summary']})
        except (ValueError, KeyError):
            continue
    result['product_coverage'] = coverage
    summary['suites'].append(result)
    (out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
    if was_interrupted:
        break
summary['finished_at'] = datetime.now(timezone.utc).isoformat()
(out / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')
print(str(out / 'results.json'))
sys.exit(0 if all(s['status'] == 'passed' for s in summary['suites']) else 1)
