import std/[os, json]
import ../src/starpkg/targets
let file = getTempDir() / "star-cli-target-test.txt"
writeFile(file, "one.invalid\ntwo.invalid\n")
target("test", "not-the-lines", "actor", bulk=true, input=file)
removeFile(file)
