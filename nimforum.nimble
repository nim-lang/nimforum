[Package]
name          = "nimforum"
version       = "0.1.0"
author        = "Dominik Picheta"
description   = "Nim forum"
license       = "MIT"

bin = "forum"

[Deps]
Requires: "nim >= 0.14.0, cairo#head, jester#head, bcrypt#head"
