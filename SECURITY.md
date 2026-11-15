# Security policy

IsolynV2.0 is a research project: a C++ game engine, a Swift bridge, a macOS
app, and an offline lab that runs the engine against itself. It handles no
accounts, no payments and no user data. That does not mean it has no security
surface — it parses generated corpora, it spawns child processes, and it is now
publicly readable — so reports are welcome and taken seriously.

## Supported versions

Only `main`. There are no releases, no maintenance branches and no backports;
a fix lands on `main` or it does not exist.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private reporting: go to the **Security** tab of this repository and
choose **Report a vulnerability**. That opens a private advisory visible only to
you and the maintainer, and it is the fastest route.

If that form is unavailable, open a normal issue containing only the sentence
"I have a security report and need a private channel" — with no technical
detail — and a private channel will be arranged.

Please include what you did, what happened, and what you expected, ideally with
the exact command and commit hash. A reproduction is worth more than a rating.

## What counts

- **Hidden-information leaks.** The engine is supposed to act only on what a
  player could legally know. A path where an AI decision is demonstrably
  influenced by an opponent's concealed tiles, the undealt boneyard, or a
  private look is a security bug, not a strength bug. This is the highest-value
  class of report in this project.
- **Rulebook violations reachable from input.** A crafted sequence that drives
  the engine into an illegal state, a corrupted score, or a crash.
- **Memory safety** in the C++ engine or the Swift/C++ bridge: out-of-bounds
  access, use-after-free, undefined behaviour reachable from a legal-looking
  game record.
- **Command or path injection** in the lab tooling, which builds shell commands
  from run identifiers, seeds and file paths.
- **Secrets.** Any credential, token or key found committed anywhere in the
  history. Note that the history is public and permanent — such a value must be
  treated as already leaked and rotated, not merely removed.

## What is not a security issue

- Playing strength. "The engine plays badly here" is an engine question; the
  measurement rules live in `docs/research/STRENGTH_BASELINE.md`.
- Rule interpretation. `docs/rules/RULEBOOK.md` is tier 0; disagreements about
  what the rules mean belong in an issue, not an advisory.
- Denial of service against a local self-play run you started yourself.
- Anything requiring an attacker who already has your unlocked machine.

## What to expect

This is a single-maintainer project with no bounty programme and no response
SLA. Expect an acknowledgement within a few days and an honest answer about
whether and when a fix is coming. If a report is valid, you will be credited in
the advisory unless you ask otherwise.

## For contributors

- Never commit a credential. Use environment variables or an untracked file.
- Run `python3 scripts/docs_audit.py` and `python3 scripts/rules_audit.py` before
  pushing; CI runs both and will fail the branch if either regresses.
- Treat everything pushed here as world-readable forever. Publication cannot be
  undone, and neither can a leaked key.
