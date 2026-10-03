import std/json
import canonical_document

proc target*(dataset, target, actor: string, bulk, recurring: bool = false,
             input: string = "", options: string = "", delay: int = 0) =
  let option = if options.len == 0: newJObject() else: parseJson(options)
  if bulk:
    let targetFile = open(input, fmRead)
    defer: targetFile.close()
    for line in targetFile.lines:
      echo targetDocument(dataset, line, actor, recurring, option, delay)
  else:
    echo targetDocument(dataset, target, actor, recurring, option, delay)
