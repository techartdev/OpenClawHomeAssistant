"""Exercise the real startup proxy block without starting the add-on or Node."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ProxyPreloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.shim = self.root / "proxy-shim.cjs"
        self.shim.write_text("// test fixture\n", encoding="utf-8")
        self.npm_marker = self.root / "npm-called"
        npm = self.root / "npm"
        npm.write_text(
            '#!/bin/sh\n: > "$PROXY_TEST_NPM_MARKER"\n'
            'printf "%s\\n" /test/global/node_modules\n',
            encoding="utf-8",
        )
        npm.chmod(0o755)
        run = Path(__file__).resolve().parents[1] / "openclaw_assistant/run.sh"
        source = run.read_text(encoding="utf-8")
        start = source.index("# Proxy shim for undici/OpenClaw startup")
        end = source.index("# Auto-configure MCP", start)
        self.block = source[start:end].replace(
            "/usr/local/lib/openclaw-proxy-shim.cjs", str(self.shim)
        )

    def run_block(self, **variables):
        # Do not inherit real proxy settings or NODE_OPTIONS from the test host.
        env = {
            "PATH": str(self.root) + os.pathsep + os.environ.get("PATH", "/usr/bin:/bin"),
            "PROXY_TEST_NPM_MARKER": str(self.npm_marker),
            **variables,
        }
        script = self.block + '\nprintf "%s\\n" "${NODE_OPTIONS-unset}" "${OPENCLAW_GLOBAL_NODE_MODULES-unset}"\n'
        result = subprocess.run(
            ["bash", "-euo", "pipefail", "-c", script],
            env=env, text=True, capture_output=True, check=True,
        )
        return result.stdout.splitlines()

    def test_no_proxy_does_not_add_preload_or_run_npm(self):
        self.assertEqual(self.run_block(), ["unset", "unset"])
        self.assertFalse(self.npm_marker.exists())

    def test_empty_proxy_variables_do_not_activate_shim(self):
        self.assertEqual(
            self.run_block(HTTP_PROXY="", HTTPS_PROXY="", http_proxy="", https_proxy=""),
            ["unset", "unset"],
        )

    def test_each_supported_proxy_variable_activates_shim(self):
        for key in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"):
            with self.subTest(variable=key):
                self.assertEqual(
                    self.run_block(**{key: "http://proxy.invalid:3128"}),
                    [f"--require {self.shim}", "/test/global/node_modules"],
                )
                self.assertTrue(self.npm_marker.exists())

    def test_no_proxy_preserves_existing_node_options_exactly(self):
        options = "--max-old-space-size=1536 --dns-result-order=ipv4first"
        self.assertEqual(self.run_block(NODE_OPTIONS=options), [options, "unset"])

    def test_proxy_preserves_existing_options_after_preload(self):
        options = "--max-old-space-size=1536 --dns-result-order=ipv4first"
        self.assertEqual(
            self.run_block(HTTPS_PROXY="http://proxy.invalid:3128", NODE_OPTIONS=options),
            [f"--require {self.shim} {options}", "/test/global/node_modules"],
        )

    def test_missing_shim_does_not_add_preload(self):
        self.shim.unlink()
        self.assertEqual(
            self.run_block(HTTP_PROXY="http://proxy.invalid:3128"), ["unset", "unset"]
        )
        self.assertFalse(self.npm_marker.exists())

    def test_all_proxy_alone_matches_shim_non_activation(self):
        self.assertEqual(
            self.run_block(ALL_PROXY="socks5://proxy.invalid:1080"), ["unset", "unset"]
        )

    def test_operator_supplied_preload_is_not_silently_removed(self):
        options = "--require /operator/custom.cjs"
        self.assertEqual(self.run_block(NODE_OPTIONS=options), [options, "unset"])


if __name__ == "__main__":
    unittest.main()
