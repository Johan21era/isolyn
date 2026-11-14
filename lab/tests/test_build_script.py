from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "tools" / "selfplay" / "build.sh"


class BuildScriptTests(unittest.TestCase):
    def _run(self, platform: str):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake = root / "bin"
            fake.mkdir()
            uname = fake / "uname"
            uname.write_text(
                "#!/bin/sh\n"
                "if [ \"${1:-}\" = \"-s\" ]; then printf '%s\\n' \"$FAKE_UNAME\"; "
                "else /usr/bin/uname \"$@\"; fi\n",
                encoding="utf-8",
            )
            uname.chmod(0o755)
            compiler = fake / "fake-cxx"
            compiler.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$@\" > \"$ARGS_FILE\"\n"
                "out=''\n"
                "prev=''\n"
                "for arg in \"$@\"; do\n"
                "  if [ \"$prev\" = '-o' ]; then out=\"$arg\"; fi\n"
                "  prev=\"$arg\"\n"
                "done\n"
                "[ -n \"$out\" ] || exit 3\n"
                "mkdir -p \"$(dirname \"$out\")\"\n"
                ": > \"$out\"\n",
                encoding="utf-8",
            )
            compiler.chmod(0o755)
            args_file = root / "args.txt"
            output = root / "build"
            env = os.environ.copy()
            env.update({
                "PATH": f"{fake}:{env['PATH']}",
                "FAKE_UNAME": platform,
                "CXX": "fake-cxx",
                "ARGS_FILE": str(args_file),
                "ISOLYN_SELFPLAY_OUT": str(output),
            })
            result = subprocess.run(["bash", str(BUILD)], capture_output=True, text=True, env=env)
            args = args_file.read_text(encoding="utf-8").splitlines() if args_file.exists() else []
            return result, args, (output / "selfplay").is_file()

    def test_linux_omits_macos_framework_and_keeps_pthread(self) -> None:
        result, args, output_exists = self._run("Linux")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-pthread", args)
        self.assertNotIn("-framework", args)
        self.assertTrue(output_exists)

    def test_macos_links_security_framework(self) -> None:
        result, args, _output_exists = self._run("Darwin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-framework", args)
        self.assertIn("Security", args)

    def test_unsupported_platform_is_refused(self) -> None:
        result, _args, _output_exists = self._run("FreeBSD")
        self.assertEqual(result.returncode, 2)
        self.assertIn("unsupported platform", result.stderr)


if __name__ == "__main__":
    unittest.main()
