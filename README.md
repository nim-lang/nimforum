# nimforum

NimForum is a light-weight forum implementation
with many similarities to Discourse. It is implemented in
the [Nim](https://nim-lang.org) programming
language and uses SQLite for its database.

## Examples in the wild

[![forum.nim-lang.org](https://i.imgur.com/hdIF5Az.png)](https://forum.nim-lang.org)

## Dependencies

The following lists the dependencies which you may need to install manually
in order to get NimForum running, compiled*, or tested†.

* libsass
* SQLite
* pcre
* Nim (and the Nimble package manager)*
* [geckodriver](https://github.com/mozilla/geckodriver)†
  * Firefox†

[*] Build time dependencies

[†] Test time dependencies

## Development

Check out the tasks defined by this project's ``nimforum.nimble`` file by
running ``nimble tasks``, as of writing they are:

```
backend              Compiles and runs the forum backend
runbackend           Runs the forum backend
frontend             Builds the necessary JS frontend (with CSS)
minify               Minifies the JS using Google's closure compiler
testdb               Creates a test DB (with admin account!)
devdb                Creates a test DB (with admin account!)
blankdb              Creates a blank DB
test                 Runs tester
fasttest             Runs tester without recompiling backend
```

Development typically involves running `nimble backend` which compiles
and runs the forum's backend, and `nimble frontend` separately to build
the frontend. When making changes to the frontend it should be enough to
simply run `nimble frontend` again to rebuild. This command will also
build the SASS ``nimforum.scss`` file in the `public/css` directory.


# Copyright

Copyright (c) 2012-2018 Andreas Rumpf, Dominik Picheta.

All rights reserved.

# License

NimForum is licensed under the MIT license.
