#!/usr/bin/env python3
"""Export native driver output without private fixture credentials."""
import json
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parent
results = ROOT / "results"
text = (results / "native-test.log").read_text()
for account in json.loads((ROOT / "session.json").read_text()).values():
    for key in ["password", "accessToken"]:
        if account.get(key):
            text = text.replace(account[key], "[REDACTED]")
text = re.sub(r'(?i)(api_key|access_token|token|accesstoken)([=": ]+)([^&\s",}]+)', r"\1\2[REDACTED]", text)
(results / "native-test-sanitized.log").write_text(text)
print("Sanitized native driver log exported.")
