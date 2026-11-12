from __future__ import annotations

import argparse
import sys
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
        sub.add_argument("--input", type=Path, help="self-play CSV to analyze (evaluate only)")
        sub.add_argument(
            "--dry-run",
            action="store_true",
            help="validate wiring without running the command",
        )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    print(f"isolyn-lab: {args.command}")
    print(f"config: {args.config}")

    if args.dry_run:
        print("dry run: wiring is present; no work was executed.")
        return 0

    if args.command == "selfplay":
        print(f"build the C++ harness: {ROOT / 'tools' / 'selfplay' / 'build.sh'}")
        print(f"then run: {SELFPLAY} --help")
    elif args.command == "evaluate":
        if args.input is None:
            print("evaluate requires --input PATH (a tools/selfplay CSV)", file=sys.stderr)
            return 2
        try:
            games = dataset.load_games(args.input)
            report = calibration.analyze(games)
        except (OSError, ValueError) as exc:
            print(f"could not read {args.input}: {exc}", file=sys.stderr)
            return 2
        mode = games[0].mode if games else "unknown"
        print(calibration.render(report, mode=mode))
        return 0
    else:
        print("This command will consume tools/selfplay output. No trainer exists yet.")

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
