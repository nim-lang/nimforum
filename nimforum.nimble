[Package]
name          = "nimforum"
version       = "0.1.0"
author        = "Dominik Picheta"
description   = "Nim forum"
license       = "MIT"

bin = "forum"

[Deps]
Requires: "nimrod >= 0.10.3, cairo#head, jester#head, bcrypt#head"
