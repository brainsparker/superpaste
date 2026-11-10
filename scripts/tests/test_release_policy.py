import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_policy', Path(__file__).parents[1]/'release_policy.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class ReleasePolicyTests(unittest.TestCase):
    def test_changed_bits_require_a_new_identity(self):
        for version, build in [('1.1.0', '3'), ('1.2.0', '2'), ('1.2.0', '1')]:
            with self.assertRaises(policy.PolicyError):
                policy.validate_versions(version, build, [('v1.1.0', '2')])
        policy.validate_versions('1.2.0', '3', [('v1.1.0', '2')])

    def test_public_skips_and_missing_credentials_fail_before_build(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            info = repo/'SuperPaste/Resources/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.2.0', 'CFBundleVersion': '3'}))
            with self.assertRaises(policy.PolicyError):
                policy.preflight(repo, skip_notarize=True)
            calls = []
            def fake(args, cwd):
                calls.append(args)
                return ''
            with self.assertRaises(policy.PolicyError):
                policy.preflight(repo, run=fake)
            self.assertEqual(calls[-1][0], 'security')
            policy.preflight(repo, local=True, skip_notarize=True, run=lambda *_: self.fail('local checks contacted services'))

    def test_dirty_tree_blocks_public_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            info = repo/'SuperPaste/Resources/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleShortVersionString':'1.2.0','CFBundleVersion':'3'}))
            with self.assertRaises(policy.PolicyError):
                policy.preflight(repo, run=lambda *_: ' M changed.swift')

    def test_architecture_gate_checks_app_and_embedded_macho(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)/'Test.app'
            main = app/'Contents/MacOS/SuperPaste'
            embedded = app/'Contents/Frameworks/Test.framework/Test'
            for path in [main, embedded]:
                path.parent.mkdir(parents=True)
                path.write_bytes(b'\xcf\xfa\xed\xfe' + b'payload')
            calls=[]
            policy.verify_architectures(app, run=lambda args,_: calls.append(args))
            self.assertEqual(len(calls),2)
            self.assertTrue(all(args[2:5] == ['-verify_arch','arm64','x86_64'] for args in calls))
            def reject(*_):
                raise policy.subprocess.CalledProcessError(1, 'lipo')
            with self.assertRaises(policy.subprocess.CalledProcessError):
                policy.verify_architectures(app, run=reject)


if __name__ == '__main__':
    unittest.main()
