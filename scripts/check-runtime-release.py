"""Verify the CLI, Router and maintained Nim runtime consume one StarLang release."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
runtime = Path(sys.argv[1])
router = Path(sys.argv[2])
lock = json.loads((root / "schema/starintel-schema.lock.json").read_text())
runtime_lock = json.loads((runtime / "schema/starintel-schema.lock.json").read_text())
router_lock = json.loads((router / "schema/starintel-schema.lock.json").read_text())

metadata = (
    "canonical_repository", "canonical_commit", "release_version", "schema_version",
    "authority_library", "canonical_key_style", "release_lock_path", "schema_path",
    "manifest_path",
)
for other, label in ((runtime_lock, "runtime"), (router_lock, "router")):
    for key in metadata:
        assert lock[key] == other[key], f"CLI/{label} {key} differs"

def closure(value):
    return {entry["source"]: entry["sha256"] for entry in value["vendored_files"].values()}

expected = closure(lock)
assert expected == closure(runtime_lock), "CLI/runtime canonical source closure differs"
assert expected == closure(router_lock), "CLI/router canonical source closure differs"

for base, value, label in ((root, lock, "CLI"), (runtime, runtime_lock, "runtime"), (router, router_lock, "router")):
    for local, entry in value["vendored_files"].items():
        actual = hashlib.sha256((base / local).read_bytes()).hexdigest()
        assert actual == entry["sha256"], f"{label}: {local}"

nim_pin = "0ba29aaa6fd0260a11d9d3a55067057ab4bdd6bc"
router_pin = "f46fdf864e5284e2f690c11b24ffd73d7d161c5b"
nimble = (root / "star.nimble").read_text()
assert f"starintel-doc.nim.git#{nim_pin}" in nimble
assert f"starRouter.git#{router_pin}" in nimble
flake_lock = json.loads((root / "flake.lock").read_text())
assert flake_lock["nodes"]["starintel-doc"]["locked"]["rev"] == nim_pin
assert flake_lock["nodes"]["star-router"]["locked"]["rev"] == router_pin

legacy = "schemas/legacy/starintel-doc-v0.9.0.schema.json"
runtime_legacy = runtime / "src/starintel_doc/schemas/legacy/starintel-doc-v0.9.0.schema.json"
assert (root / legacy).read_bytes() == runtime_legacy.read_bytes(), "historical compatibility schema drift"
assert (root / legacy).read_bytes() == (router / legacy).read_bytes(), "router historical compatibility schema drift"
print("CLI, Router and Nim runtime agree on the canonical StarLang source closure")
