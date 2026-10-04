import std/[json, md5]
import ./documents

proc createTarget*(dataset, value, actor: string, delay = 0, recurring = false,
                   options = newJObject()): JsonNode =
  result = %*{"id": $toMD5(dataset & value & actor & $recurring & $delay),
              "dataset": dataset, "dtype": "target", "schemaVersion": "0.10.1",
              "target": value, "actor": actor, "delay": delay,
              "recurring": recurring, "options": options}
  validateDocument(result)

proc target*(dataset, target, actor: string, bulk = false, recurring = false,
             input = "", options = "", delay = 0) =
  let option = if options.len == 0: newJObject() else: parseJson(options)
  if bulk:
    let path = if input.len > 0: input else: target
    let stream = open(path)
    defer: stream.close()
    for line in stream.lines:
      echo createTarget(dataset, line, actor, delay, recurring, option)
  else:
    echo createTarget(dataset, target, actor, delay, recurring, option)
