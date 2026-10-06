import starRouter
import database
import std/[asyncdispatch, json]
import documents
import strformat

proc publishDoc*(client: Client, doc: JsonNode, topic: string) {.async.} =
  let msg = newMessage(doc, proto.newDocument, "", topic)
  await client.emit(msg)

proc publishTarget(client: Client, doc: JsonNode, actor: string) {.async.} =
  validateDocument(doc)
  if doc["dtype"].getStr != "target": raise newException(ValueError, "target input requires a target document")
  let msg = newMessage(doc, proto.target, "", actor)
  await client.emit(msg)

proc publishDocuments*(apiAddress: string = "tcp://127.0.0.1:6001", subAddress: string = "tcp://127.0.0.1:6000", isTarget: bool = false, topic: string = "", actor: string = "", path: string) =
  var client = newClient("starcli", subAddress, apiAddress, 6, @[""])
  let f = open(path, fmRead)
  defer: f.close()
  waitFor client.connect()
  if isTarget:
    for line in f.lines:
      waitFor client.publishTarget(line.parseJson(), actor)
  else:
    for line in f.lines:
      waitFor client.publishDoc(line.parseJson(), topic)

proc allMsg(doc: Message[JsonNode]): bool =
  return true

proc echoMsg(doc: Message[JsonNode]) {.async.} =
  echo doc.data

proc subscribe*(apiAddress: string = "tcp://127.0.0.1:6001", subAddress: string = "tcp://127.0.0.1:6000", queueSize: int = 100, isActor: bool = false, topic, actor: string = "") =
  var client: Client
  var inbox = JsonNode.newInbox(queueSize)
  if isActor:
    client = newClient(fmt"starcli|{actor}", subAddress, apiAddress, 6, @[""])
  else:
    client = newClient(fmt"starcli", subAddress, apiAddress, 6, @[""])
  waitFor client.connect()
  inbox.registerFilter(allMsg)
  inbox.registerCB(echoMsg)
  waitFor runInbox(JsonNode, client, inbox)
