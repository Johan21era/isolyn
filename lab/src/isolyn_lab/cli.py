from __future__ import annotations

import argparse
import json
import sys
from itertools import chain
from pathlib import Path

from . import calibration, dataset

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG = ROOT / "lab" / "configs" / "selfplay.example.toml"
SELFPLAY = ROOT / "tools" / "selfplay" / "build" / "selfplay"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="isolyn-lab",
        description="Offline Isolyn lab. Calibration reports are real; training remains scaffolded.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, help_text in (
        ("selfplay", "generate self-play games and calibration data"),
        ("train", "fit an evaluation model from self-play data"),
        ("evaluate", "measure a candidate against a baseline ladder"),
    ):
        sub = subparsers.add_parser(command, help=help_text)
        sub.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
        sub.add_argument(
            "--input",
            type=Path,
            action="append",
            help="self-play CSV to analyze (evaluate only); repeat for several analyses",
        )
        sub.add_argument(
            "--json",
            action="store_true",
            help="emit machine-readable JSON instead of a text report",
        )
        sub.add_argument(
            "--dry-run",
            action="store_true",
            help="validate wiring without running the command",
        )
    return parser


def _evaluate(args: argparse.Namespace) -> int:
    inputs: list[Path] = args.input or []
    if not inputs:
        print("evaluate requires --input PATH (repeat the flag to analyze several CSVs)", file=sys.stderr)
        return 2

    reports = []
    for path in inputs:
        try:
            games = dataset.iter_games(path)
            first = next(games, None)
            mode = first.mode if first is not None else "unknown"
            report = calibration.analyze(chain((first,), games) if first is not None else ())
        except (OSError, ValueError) as exc:
            print(f"could not read {path}: {exc}", file=sys.stderr)
            return 2
        reports.append((path, mode, report))

    if args.json:
        payload = [
            calibration.report_to_dict(report, mode=mode, input_path=str(path.resolve()))
            for path, mode, report in reports
        ]
        print(json.dumps(payload, indent=2))
        return 0

    for index, (path, mode, report) in enumerate(reports):
        if index:
            print()
        print(f"isolyn-lab: evaluate  {path}")
        print(calibration.render(report, mode=mode))
    return 0


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if args.command == "evaluate" and not args.dry_run:
        return _evaluate(args)

    print(f"isolyn-lab: {args.command}")
    print(f"config: {args.config}")

    if args.dry_run:
        print("dry run: wiring is present; no work was executed.")
        return 0

    if args.command == "selfplay":
        print(f"build the C++ harness: {ROOT / 'tools' / 'selfplay' / 'build.sh'}")
        print(f"then run: {SELFPLAY} --help")
    else:
        print("This command will consume tools/selfplay output. No trainer exists yet.")

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
