## Wire semantics come only from the pinned StarLang-generated runtime.
import std/json
import starintel_doc/canonical as canonical
import starintel_doc/v090 as historical
const Compatibility = staticRead("../../schemas/starintel-0.10.1/compatibility.json")
const HistoricalSchema = staticRead("../../schemas/legacy/starintel-doc-v0.9.0.schema.json")
proc parseWireDocument*(text: string): JsonNode =
  ## Preflight every profile with the canonical strict raw parser so duplicate
  ## decoded keys and non-JSON syntax are rejected before materialization.
  let wire = canonical.parseWireJson(text)
  if wire.kind == JObject and wire.hasKey("schema_version") and
      wire["schema_version"].kind == JString and wire["schema_version"].getStr == "0.9.0":
    # The archived 0.9 validator expects ordinary Nim numeric JsonNode kinds.
    # Reparse only after strict raw preflight has proven the wire unambiguous.
    return parseJson(text)
  wire
proc validateDocument*(document: JsonNode) =
  if document.kind != JObject: raise newException(ValueError, "document must be an object")
  if document.hasKey("schemaVersion"):
    let checked = canonical.validateDocument(document)
    if not checked.ok: raise newException(ValueError, checked.category & ": " & checked.message)
  elif document.hasKey("schema_version") and document["schema_version"].kind == JString and
      document["schema_version"].getStr == "0.9.0" and
      %"0.9.0" in parseJson(Compatibility)["acceptedSchemaVersions"].getElems:
    let checked = historical.validateDocument(document, parseJson(HistoricalSchema))
    if not checked.ok: raise newException(ValueError, checked.category & ": " & checked.message)
  else: raise newException(ValueError, "unsupported StarIntel schema version")
proc couchDocument*(document: JsonNode): JsonNode =
  validateDocument(document)
  result = document.copy()
  if result.hasKey("id"):
    result["_id"] = result["id"]
    result.delete("id")
    if result.hasKey("rev"):
      result["_rev"] = result["rev"]
      result.delete("rev")
