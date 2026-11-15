#!/usr/bin/env python3
"""Security gate: what a reader of this repository could take away.

This is not a linter. It answers four questions that matter for a public
research repository, and fails the build when the answer changes:

1. Did a credential ever enter the tree or the history?  The history is public
   and permanent, so a secret removed in a later commit is still leaked.
2. Is a file type tracked that should never be — key material, an env file, a
   cloud CLI credential?
3. Does the tree expose a local absolute home path?  The account name is not a
   secret, but it is not something a repository needs to advertise either.
4. Does the code still hold its own guards?  The run-id pattern is the only
   thing keeping a user-supplied string out of a filesystem path, and a
   refactor that drops it would be a path-traversal bug, not a style change.

Everything here is stdlib and read-only. It never edits a file and never
touches the network.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Deliberately narrow: each pattern needs enough entropy that a documentation
# mention of the prefix (which is common in this repository's security notes)
# cannot match. A false positive here costs a build; a false negative costs a
# credential.
SECRET_PATTERNS = [
    ("GitHub token", re.compile(r"ghp_[A-Za-z0-9]{20,}")),
    ("GitHub fine-grained token", re.compile(r"github_pat_[A-Za-z0-9_]{20,}")),
    ("GitHub OAuth token", re.compile(r"gho_[A-Za-z0-9]{20,}")),
    ("AWS access key id", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("OpenAI-style key", re.compile(r"\bsk-[A-Za-z0-9]{20,}")),
    ("Slack token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("Google API key", re.compile(r"AIza[0-9A-Za-z_-]{35}")),
    ("Private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("JWT", re.compile(r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.")),
]

# A file whose name matches would be a finding even if it is empty: the name
# alone tells a reader where a credential lives.
FORBIDDEN_NAMES = re.compile(
    r"(^|/)(\.env(\..*)?|\.netrc|kaggle\.json|credentials(\.json)?|id_rsa|id_ed25519"
    r"|[^/]*\.(pem|p12|pfx|keystore|jks))$",
    re.IGNORECASE,
)

# Dated audit reports quote the absolute path the audit ran at. They are
# receipts for a specific day and are not rewritten (docs rule §5), so the path
# is excused there and nowhere else.
ABSOLUTE_PATH_ALLOWLIST = ("docs/audits/",)

# Labels are chosen so they cannot match their own pattern: an earlier version
# used the literal code forms as labels and the scanner promptly reported itself
# three times. The regular expressions never matched their own source text; the
# human-readable strings did. Keep it that way.
DANGEROUS_PYTHON = [
    ("a shell subprocess", re.compile(r"shell\s*=\s*True")),
    ("os.system", re.compile(r"\bos\.system\s*\(")),
    ("os.popen", re.compile(r"\bos\.popen\s*\(")),
    ("dynamic eval", re.compile(r"(?<![\w.])eval\s*\(")),
    ("dynamic exec", re.compile(r"(?<![\w.])exec\s*\(")),
    ("pickle.loads", re.compile(r"pickle\.loads?\s*\(")),
    ("yaml.load", re.compile(r"yaml\.load\s*\(")),
    ("tarfile.extractall", re.compile(r"extractall\s*\(")),
]

DANGEROUS_C = [
    ("strcpy", re.compile(r"\bstrcpy\s*\(")),
    ("strcat", re.compile(r"\bstrcat\s*\(")),
    ("sprintf", re.compile(r"\bsprintf\s*\(")),
    ("gets", re.compile(r"\bgets\s*\(")),
    ("alloca", re.compile(r"\balloca\s*\(")),
]

BINARY_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".icns", ".pdf", ".zip", ".gz", ".o", ".a"}
TEXT_SUFFIXES = {".py", ".swift", ".cpp", ".hpp", ".h", ".md", ".sh", ".json", ".yml", ".yaml",
                 ".txt", ".csv", ".toml", ".js", ".html", ".xml", ".plist", ".c", ".mm"}

HOME_PATH = re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+")

# The guard that keeps a run id from escaping the runs directory. Three modules
# carry their own copy; all three must still exist and agree.
RUN_ID_GUARD = re.compile(r"RUN_ID_PATTERN\s*=\s*re\.compile\(r\"\^\[A-Za-z0-9\]")
RUN_ID_USERS = ("lab/src/isolyn_lab/runner.py", "lab/src/isolyn_lab/cloud.py",
                "lab/src/isolyn_lab/report.py")


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def tracked_files() -> list[str]:
    return [name for name in git("ls-files", "-z").split("\0") if name]


def read_text(path: Path) -> str | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\0" in data[:8192]:
        return None
    return data.decode("utf-8", errors="ignore")


def check_secrets(files: list[str]) -> list[str]:
    findings = []
    for name in files:
        path = ROOT / name
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        text = read_text(path)
        if text is None:
            continue
        for label, pattern in SECRET_PATTERNS:
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{name}:{line} looks like a {label}")
    return findings


def check_history() -> list[str]:
    """Every blob ever committed, because a secret is leaked on arrival."""
    findings = []
    for label, pattern in SECRET_PATTERNS:
        for match in pattern.finditer(git("log", "--all", "-p", "--no-color")):
            findings.append(f"history contains something that looks like a {label}")
            break
    return findings


def check_forbidden(files: list[str]) -> list[str]:
    return [f"{name} is a credential-shaped file that must not be tracked"
            for name in files if FORBIDDEN_NAMES.search(name)]


def check_absolute_paths(files: list[str]) -> list[str]:
    findings = []
    for name in files:
        if name.startswith(ABSOLUTE_PATH_ALLOWLIST):
            continue
        path = ROOT / name
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        text = read_text(path)
        if text is None:
            continue
        hits = HOME_PATH.findall(text)
        if hits:
            findings.append(f"{name} exposes {len(hits)} local path(s), e.g. {hits[0]}")
    return findings


def check_constructs(files: list[str], rules, suffixes) -> list[str]:
    findings = []
    for name in files:
        if Path(name).suffix.lower() not in suffixes:
            continue
        text = read_text(ROOT / name)
        if text is None:
            continue
        for label, pattern in rules:
            match = pattern.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                findings.append(f"{name}:{line} uses {label}")
    return findings


def check_run_id_guards() -> list[str]:
    findings = []
    seen = set()
    for name in RUN_ID_USERS:
        text = read_text(ROOT / name) or ""
        match = RUN_ID_GUARD.search(text)
        if not match:
            findings.append(f"{name} no longer defines the run-id pattern")
            continue
        seen.add(match.group(0))
    if len(seen) > 1:
        findings.append("run-id patterns disagree between modules; they must be identical")
    return findings


def check_dependencies() -> tuple[list[str], str]:
    """A dependency you do not have cannot be vulnerable."""
    pyproject = read_text(ROOT / "lab/pyproject.toml") or ""
    python_deps = 0 if re.search(r"^dependencies\s*=\s*\[\s*\]", pyproject, re.MULTILINE) else None
    resolved = ROOT / "Package.resolved"
    swift_deps = 0
    if resolved.exists():
        swift_deps = (read_text(resolved) or "").count('"identity"')
    findings = []
    if python_deps is None:
        findings.append("lab/pyproject.toml declares runtime dependencies; audit them")
    if swift_deps > 3:
        findings.append(f"Package.resolved pulls {swift_deps} packages; audit them")
    summary = f"{python_deps if python_deps is not None else '?'} python, {swift_deps} swift"
    return findings, summary


def main() -> int:
    files = tracked_files()
    commits = git("rev-list", "--count", "--all").strip()

    findings: dict[str, list[str]] = {}
    dependencies, dependency_summary = check_dependencies()

    findings["secret-patterns"] = check_secrets(files)
    findings["history-secrets"] = check_history()
    findings["forbidden-files"] = check_forbidden(files)
    findings["absolute-paths"] = check_absolute_paths(files)
    findings["dangerous-python"] = check_constructs(
        files, DANGEROUS_PYTHON, {".py", ".sh"})
    findings["dangerous-c"] = check_constructs(
        files, DANGEROUS_C, {".cpp", ".hpp", ".h", ".c", ".mm"})
    findings["run-id-guards"] = check_run_id_guards()
    findings["dependencies"] = dependencies

    print("Security audit")
    print(f"  tracked files      : {len(files)}")
    print(f"  commits in history : {commits}")
    print(f"  dependency surface : {dependency_summary}")

    total = 0
    for name, items in findings.items():
        total += len(items)
        state = "PASS" if not items else f"FAIL ({len(items)})"
        print(f"  {name:<19}: {state}")
        for item in items:
            print(f"      {item}")

    print()
    if total:
        print(f"RESULT: FAIL — {total} finding(s); see the list above")
        return 1
    print("RESULT: PASS — no credential, forbidden file, exposed path or lost guard")
    return 0


if __name__ == "__main__":
    sys.exit(main())
