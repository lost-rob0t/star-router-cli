import std/json
import ../src/starpkg/canonical_document
let doc = targetDocument("test", "example.invalid", "actor", false, %*{"opaque": nil}, 0)
doAssert doc["schemaVersion"].getStr == "0.10.1"
doAssert doc["dtype"].getStr == "target"
doAssert doc["recurring"].getBool == false
doAssert not doc.hasKey("_id")
doAssert targetDocument("test", "other.invalid", "actor", false, newJObject(), 0)["id"] != doc["id"]
let stored = storageDocument(doc)
doAssert stored["id"] == doc["id"] and stored["_id"] == doc["id"]
doAssert not doc.hasKey("_id")
var rejected = false
try: discard targetDocument("test", "x", "actor", false, newJNull(), 0)
except ValueError: rejected = true
doAssert rejected
var old = parseJson($doc)
old.delete("schemaVersion")
rejected = false
try: discard storageDocument(old)
except ValueError: rejected = true
doAssert rejected
echo "canonical CLI boundary checks passed"
