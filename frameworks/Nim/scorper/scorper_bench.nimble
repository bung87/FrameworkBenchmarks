# Package

version       = "0.1.0"
author        = "bung87"
description   = "A new awesome scorper package"
license       = "MIT"
srcDir        = "."
bin           = @["scorper_bench"]

backend       = "c"

# Dependencies

requires "nim >= 1.2.0"
requires "scorper >= 1.0.7"
requires "amysql >= 0.7.3"
requires "karax"
