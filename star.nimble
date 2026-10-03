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
requires "https://github.com/lost-rob0t/starintel-doc.nim.git#827f2c072e9893561a1925c47f898458bafd6759"
# Broken!
# Will Be re-added, just a temp fix
# requires "https://github.com/lost-rob0t/starRouter.git"
requires "cligen"

task install, "installs star-cli":
  switch("define", "release")
  switch("define", "ssl")
  switch("opt", "speed")
  setCommand "c"
