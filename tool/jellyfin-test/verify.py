#!/usr/bin/env python3
"""Print only sanitized local-fixture state, never credentials or tokens."""
import json
import stat
from setup import ROOT, STATE, api

state = json.loads(STATE.read_text())
admin = state["admin"]
viewer = state["viewer"]
user = api("GET", "/Users/" + viewer["userId"], token=admin["accessToken"])
config = api("GET", "/System/Configuration", token=admin["accessToken"])
folders = api("GET", "/Library/VirtualFolders", token=admin["accessToken"])
items = api("GET", "/Users/" + viewer["userId"] + "/Items?recursive=true&includeItemTypes=Movie,Episode&fields=MediaStreams,MediaSources", token=viewer["accessToken"])["Items"]
report = {
    "server": api("GET", "/System/Info/Public"),
    "ordinaryAccount": not user["Policy"]["IsAdministrator"],
    "resumeMinimumSeconds": config.get("MinResumeDurationSeconds"),
    "privateFilesMode600": all(stat.S_IMODE(p.stat().st_mode) == 0o600 for p in [STATE, ROOT / "results/live-config.json"]),
    "libraries": [{"name": f["Name"], "paths": f["Locations"], "externalFetchersDisabled": all(not t.get("MetadataFetchers") and not t.get("ImageFetchers") for t in f["LibraryOptions"].get("TypeOptions", []))} for f in folders],
    "media": [{"name": i["Name"], "type": i["Type"], "resumeSeconds": i.get("UserData", {}).get("PlaybackPositionTicks", 0) // 10000000, "played": i.get("UserData", {}).get("Played"), "externalCaptions": sum(1 for t in i.get("MediaStreams", []) if t.get("Type") == "Subtitle" and t.get("IsExternal"))} for i in items],
}
report["server"] = {k: report["server"].get(k) for k in ["ServerName", "Version", "StartupWizardCompleted"]}
print(json.dumps(report, indent=2))
