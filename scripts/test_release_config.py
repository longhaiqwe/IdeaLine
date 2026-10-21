import base64
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("release_config", Path(__file__).with_name("release_config.py"))
config_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config_module)


class ReleaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.config = {"version": "1.1.0", "build": "2", "feed_url": "", "public_ed_key": ""}

    def test_local_build_has_no_update_network_configuration(self):
        plist = config_module.bundle_info(self.config)
        self.assertNotIn("SUFeedURL", plist)
        self.assertFalse(plist["SUEnableAutomaticChecks"])
        self.assertFalse(plist["SUAutomaticallyUpdate"])

    def test_distribution_requires_complete_configuration(self):
        with self.assertRaises(ValueError):
            config_module.bundle_info(self.config, require_updates=True)

    def test_partial_and_insecure_configuration_is_rejected(self):
        key = base64.b64encode(bytes(range(32))).decode()
        for feed, public_key in [("https://example.com/appcast.xml", ""), ("", key),
                                 ("http://example.com/appcast.xml", key),
                                 ("https://user:pass@example.com/feed.xml", key),
                                 ("https://example.com/feed.xml", "bad-key")]:
            with self.subTest(feed=feed, key=public_key):
                with self.assertRaises(ValueError):
                    config_module.bundle_info(dict(self.config, feed_url=feed, public_ed_key=public_key))

    def test_release_uses_explicit_versions_and_opt_in_installation(self):
        plist = config_module.bundle_info(dict(self.config, feed_url="https://example.com/feed.xml",
                                              public_ed_key=base64.b64encode(bytes(range(32))).decode()), require_updates=True)
        self.assertEqual(plist["CFBundleIdentifier"], "local.longhai.IdeaLine")
        self.assertEqual(plist["CFBundleVersion"], "2")
        self.assertEqual(plist["CFBundleShortVersionString"], "1.1.0")
        self.assertTrue(plist["SUEnableAutomaticChecks"])
        self.assertFalse(plist["SUAutomaticallyUpdate"])
        self.assertEqual(plist["SUScheduledCheckInterval"], 86400)

    def test_invalid_build_or_version_is_rejected(self):
        for changes in [{"version": ""}, {"version": "../bad"}, {"build": "0"}, {"build": "v2"}]:
            with self.assertRaises(ValueError):
                config_module.bundle_info(dict(self.config, **changes))


if __name__ == "__main__":
    unittest.main()
