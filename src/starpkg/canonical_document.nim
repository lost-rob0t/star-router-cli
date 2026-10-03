import std/[json, md5]
import starintel_doc/canonical

proc checkedDocument*(document: JsonNode): JsonNode =
  let checked = validateDocument(document)
  if not checked.ok:
    raise newException(ValueError, checked.category & ": " & checked.message)
  document

proc targetDocument*(dataset, target, actor: string, recurring: bool,
                     options: JsonNode, delay: int): JsonNode =
  let identity = $ %*[dataset, target, actor]
  result = %*{"id": "target:" & getMD5(identity), "dataset": dataset,
    "dtype": "target", "schemaVersion": "0.10.1", "target": target,
    "actor": actor, "recurring": recurring, "options": options, "delay": delay}
  discard checkedDocument(result)

proc storageDocument*(document: JsonNode): JsonNode =
  discard checkedDocument(document)
  result = parseJson($document)
  result["_id"] = result["id"]
  if result.hasKey("rev"):
    result["_rev"] = result["rev"]
    result.delete("rev")
