# nimforum

NimForum is a light-weight forum implementation
with many similarities to Discourse. It is implemented in
the [Nim](https://nim-lang.org) programming
language and uses SQLite for its database.

## Examples in the wild

[![forum.nim-lang.org](https://i.imgur.com/hdIF5Az.png)](https://forum.nim-lang.org)

<p align="center" margin="0"><a href="https://forum.nim-lang.org"><b>forum.nim-lang.org</b></a></p>

## Features

* Efficient, type safe and clean **single-page application** developed using the
  [Karax](https://github.com/pragmagic/karax) and
  [Jester](https://github.com/dom96/jester) frameworks.
* **Utilizes SQLite** making set up much easier.
* Endlessly **customizable** using SASS.
* Spam blocking via new user sandboxing with great tools for moderators.
* reStructuredText enriched by Markdown to make formatting your posts a breeze.
* Search powered by SQLite's full-text search.
* Context-aware replies.
* Last visit tracking.
* Gravatar support.
* And much more!

## Setup

[See this document.](https://github.com/nim-lang/nimforum/blob/master/setup.md)

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

To get up and running:

```bash
git clone https://github.com/nim-lang/nimforum
cd nimforum
git submodule update --init --recursive

# Setup the db with user: admin, pass: admin and some other users
nimble devdb

# Run this again if frontend code changes
nimble frontend

# Will start a server at localhost:5000
nimble backend
```


Development typically involves running `nimble devdb` which sets up the
database for development and testing, then `nimble backend`
which compiles and runs the forum's backend, and `nimble frontend`
separately to build the frontend. When making changes to the frontend it
should be enough to simply run `nimble frontend` again to rebuild. This command
will also build the SASS ``nimforum.scss`` file in the `public/css` directory.


# Copyright

Copyright (c) 2012-2018 Andreas Rumpf, Dominik Picheta.

All rights reserved.

# License

NimForum is licensed under the MIT license.
