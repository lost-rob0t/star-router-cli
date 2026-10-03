import mycouch
import json
import parsecfg
import asyncdispatch
import canonical_document
import times
import strutils
import cligen
import tables
import os
import config


proc init*(configPath: string=DEFAULT_CONFIG) =
  let config = loadConfigFile(configPath)
  if config.verbose == true:
    echo "Config: ", configPath
    echo "DB Host: ", config.dbHost
    echo "DB Port: ", $config.dbPort
    echo "DB User: ", config.dbHost
    echo "DB main-db: ", config.database
  var db = newCouchDBClient(host = config.dbHost, port = config.dbPort)
  let aresp = db.cookieAuth(config.dbUser, config.dbPass)
  try:
    db.createDB(config.database)
  except CouchDBError:
    echo "Main db exists"
  try:

    db.createDB(config.targetdb)
  except CouchDBError:
    echo "targetdb exists" # Db exists
  let targetMango = %*{"_id": "_design/targetMango",
  "_rev": "1-8cdd5eedaa22774bdcc580a7d07e2223",
  "language": "query",
  "views": {
    "actor-search": {
      "map": {
        "fields": {
          "actor": "asc",
          "target": "asc"
        },
        "partial_filter_selector": {}
      },
      "reduce": "_count",
      "options": {
        "def": {
          "fields": [
            "actor",
            "target"
          ]
        }
      }
    }
  }
  }
  let peopleDesign = %*{"_id": "_design/data",
    "views": {
    "by_lastname": {
      "map": "function (doc) {\n  if(doc.dtype == \"person\") {\n    emit(doc._id, doc.lname)\n  }\n}"
    },
    "total_people": {
      "reduce": "_sum",
      "map": "function (doc) {\n  if(doc.dtype == 'person'){\n  emit(null, 1);\n}}"
    },
    "total_address": {
      "reduce": "_sum",
      "map": "function (doc) {\n  if(doc.dtype == \"address\"){\n  emit(null, 1);\n}}"
    },
    "total_orgs": {
      "reduce": "_sum",
      "map": "function (doc) {\n  if(doc.dtype == 'org'){\n  emit(null, 1);\n}}"
    },
    "dataset_size": {
      "reduce": "_count",
      "map": "function (doc) {\n  emit(doc.dataset, 1);\n  \n}"
    },
    "total": {
      "reduce": "_sum",
      "map": "function (doc) {\n  emit(null, 1);\n}"
    },
    "source_data_size": {
      "reduce": "_count",
      "map": "function (doc) {\n  emit(doc.source_dataset, 1);\n}"
    }
  },
  "language": "javascript"
  }

  let searchDesign = %*{"_id": "_design/search",
  "views": {},
  "language": "javascript",
  "indexes": {
    "fts": {
      "analyzer": {
        "name": "perfield",
        "default": "standard",
        "fields": {
          "fname": "standard",
          "lname": "standard",
          "mname": "keyword",
          "jobs": "standard",
          "bio": "standard",
          "locations": "standard",
          "emails": "email",
          "title": "whitespace",
          "search": "standard"
        }
      },
      "index": "function(doc) { \n    if(doc.dtype == \"person\") {\n      var total = \"\"\n      if(doc.mname){\n       total = doc.lname + \" \" + doc.mname + \" \" + doc.fname + \" \" + doc.title+ \" \" + JSON.stringify(doc.orgs) + \" \" + JSON.stringify(doc.locations)\n\n      }\n      else {\n      total = doc.lname + \" \" + doc.fname + \" \" + doc.title+ \" \" + JSON.stringify(doc.orgs) + \" \" + JSON.stringify(doc.locations) + \" \" + JSON.stringify(doc.emails)\n\n  }   \n      index('fname', doc.fname, {\"store\":\"yes\", \"field\":\"fname\"})\n      index('lname', doc.lname, {\"store\":\"yes\", \"field\":\"lname\"})\n      if(doc.mname){index('mname', doc.mname, {\"store\":\"yes\", \"field\":\"mname\"})}\n      if(doc.bio){index('bio', doc.bio, {\"store\":\"yes\", \"field\":\"bio\"})}\n      index('age', doc.age, {\"store\":\"yes\", \"field\":\"age\"})\n      if(doc.title){index('title', doc.title, {\"store\":\"yes\", \"field\":\"tite\"})}\n      if(doc.orgs){index('orgs', JSON.stringify(doc.orgs), {\"store\":\"yes\", \"field\":\"orgs\"})}\n      if(doc.locations){index('locations', JSON.stringify(doc.locations), {\"store\":\"yes\", \"field\":\"locations\"})}\n      if(doc.emails){index('emails', JSON.stringify(doc.emails), {\"store\":\"yes\", \"field\":\"emails\"})}\n      if(doc.ip){index('ip', JSON.stringify(doc.orgs), {\"store\":\"yes\", \"field\":\"ip\"})}\n      index('search', total, {\"store\":\"yes\", \"field\":\"search\"})\n\n}}"
    }
  }
  }


  let targetDesign = %*{"_id": "_design/targets",
  "views": {
    "byActor": {
      "map": "function (doc) {\n  emit(doc.actor, doc._id);\n}"
    },
    "actor-target": {
      "map": "function (doc) {\n  emit(doc.actor, doc.target);\n}"
    },
    "actor-sum": {
      "reduce": "_sum",
      "map": "function (doc) {\n  emit(doc.actor, 1);\n}"
    }
  },
  "language": "javascript"
  }
  let timeDesign = %*{"_id": "_design/time",
  "language": "javascript",
  "views": {
    "byDate": {
      "reduce": "_count",
      "map": "function(doc) {\n  var date = new Date(doc.createdAt * 1000);\n  var year = date.getUTCFullYear();\n  var month = date.getUTCMonth() + 1; // Months are 0-based\n  var day = date.getUTCDate();\n  var dateStr = month + \"-\" + day + \"-\" + year;\n  emit(dateStr, 1);\n}"
    },
    "byHour": {
      "reduce": "_count",
      "map": "function(doc) {\n    var timestamp = doc.date_updated - 3600;\n    var date = new Date(timestamp * 1000);\n    var hour = date.getUTCHours();\n    emit(hour, 1);\n}"
    },
    "byDateHour": {
      "reduce": "_count",
      "map": "function(doc) {\n    var timestamp = doc.date_updated;\n    var date = new Date(timestamp * 1000);\n    var year = date.getUTCFullYear();\n    var month = (\"0\" + (date.getUTCMonth() + 1)).slice(-2);\n    var day = (\"0\" + date.getUTCDate()).slice(-2);\n    var hour = (\"0\" + date.getUTCHours()).slice(-2);\n    var dateKey = month + \"-\" + day + \"-\" + year+\"H\"+hour;\n    emit(dateKey, 1);\n}"
    },
    "byMonth": {
      "reduce": "_count",
      "map": "function(doc) {\n  var date = new Date(doc.createdAt * 1000);\n  var year = date.getUTCFullYear();\n  var month = date.getUTCMonth() + 1; // Months are 0-based\n  var dateStr = month + \"-\" + year;\n  emit(dateStr, 1);\n}"
    }
  }
  }
  try:
    discard db.createDoc(config.database, targetMango)
  except CouchDBError:
    discard
  try:
    discard db.createDoc(config.database, searchDesign)
  except CouchDBError:
    discard
  try:
    discard db.createDoc(config.database, peopleDesign)
  except CouchDBError:
    discard
  try:
    discard db.createDoc(config.targetdb, targetDesign)
  except CouchDBError:
    discard
  try:
    discard db.createDoc(config.database, timeDesign)
  except CouchDBError:
    discard

#proc format(doc: JsonNode, indent: int = 0, str: var string = ""): string =
#  if str == "":
#    str = "===DOC===\n"
#  let pairs = doc.getFields
#  for key in pairs.keys:
#    case pairs[key].kind:
#      of JObject:
#        var nstr = "\n" & indent(fmt"==={key}===:", indent) & "\n"
#        var str1 = pairs[key].format(indent + 2, nstr)
#        str &= str1
#      else:
#        str &= indent(fmt"{key}: "  & $pairs[key], indent) & "\n"
#  result = str



proc search(db: CouchDBClient, q: string): JsonNode =
  discard



proc insert*(db: CouchDBClient, config: StarConfig, docs: seq[JsonNode]) =
  var stored: seq[JsonNode]
  for doc in docs: stored.add(storageDocument(doc))
  try:
    discard db.bulkDocs(config.database, %*stored)
  except CouchDBError:
    for doc in stored:
      discard db.createDoc(config.database, doc)


proc loadData*(configPath: string, file: string, bulkSize: int = 500) {.async.} =
  if bulkSize <= 0: raise newException(ValueError, "bulkSize must be positive")
  let f = open(file)
  defer: f.close()
  let config = loadConfigFile(configPath)
  var db = newAsyncCouchDBClient(host=config.dbHost, port=config.dbPort)
  discard await db.cookieAuth(config.dbUser, config.dbPass)
  var docs: seq[JsonNode]
  for line in f.lines:
    docs.add(storageDocument(line.parseJson))
    if docs.len >= bulkSize:
      discard await db.bulkDocs(config.database, %*docs)
      docs = @[]
  if docs.len > 0:
    discard await db.bulkDocs(config.database, %*docs)

proc insert_data*(configPath: string, file: string, bulkSize: int = 500) =
  waitFor loadData(configPath, file, bulkSize)
