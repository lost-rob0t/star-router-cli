# Package

version       = "0.1.0"
author        = "nsaspy"
description   = "Manage star intel Operations and automations from the command line"
license       = "MIT"
srcDir        = "src"
bin           = @["star"]


# Dependencies

requires "nim >= 2.0.0"
requires "mycouch"
requires "https://github.com/lost-rob0t/starintel-doc.nim.git#0ba29aaa6fd0260a11d9d3a55067057ab4bdd6bc"
requires "https://github.com/lost-rob0t/starRouter.git#f46fdf864e5284e2f690c11b24ffd73d7d161c5b"
requires "cligen"

task install, "installs star-cli":
  switch("define", "release")
  switch("define", "ssl")
  switch("opt", "speed")
  setCommand "c"
