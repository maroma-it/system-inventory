"""Regression contracts for generated browser views and public-text handling."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import narrate
import regenerate


class UiContractsTests(unittest.TestCase):
    def test_brief_href_encodes_hash_and_spaces(self):
        self.assertEqual(regenerate._brief_href("Form #2"), "Form%20%232.html")

    def test_public_text_redacts_recipient_addresses(self):
        text = "Send to owner@example.com and workflow-recipient@example.com"
        cleaned = narrate.redact_public_text(text)
        self.assertNotIn("owner@example.com", cleaned)
        self.assertEqual(cleaned.count("[configured recipient]"), 2)

    def test_explorers_are_offline_and_responsive(self):
        for name in ("explorer_template.html", "global_template.html"):
            text = (ROOT / "scripts" / name).read_text(encoding="utf-8")
            self.assertNotIn("cdnjs.cloudflare.com", text)
            self.assertIn("@media(max-width:700px)", text.replace(" ", ""))
            self.assertIn("Browse nodes", text)
            self.assertIn("Content-Security-Policy", text)

    def test_brief_rows_are_native_buttons(self):
        text = (ROOT / "scripts" / "brief_template.html").read_text(encoding="utf-8")
        self.assertIn('<button type="button" class="fld', text)
        self.assertIn("aria-expanded", text)
        generator = (ROOT / "scripts" / "regenerate.py").read_text(encoding="utf-8")
        self.assertIn('id="brief-exp-count" role="status" aria-live="polite"', generator)


if __name__ == "__main__":
    unittest.main()
