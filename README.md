# nimforum

This is Nim's forum. Available at http://forum.nim-lang.org.

## Building

You can use ``nimble`` (available [here](https://github.com/nim-lang/nimble)
to get all the necessary
[dependencies](https://github.com/nim-lang/nimforum/blob/master/nimforum.nimble#L11).

Clone this repo and execute ``nimble build`` in this repositories directory.

_See also: Running the forum for how to create the database_

## Dependencies

The code depends on the RST parser of the Nim
compiler and on Jester. The captchas for registration uses the
[reCaptcha module](https://github.com/euantorano/recaptcha.nim).

#### bcrypt

On macosx you also need to make sure to use the bcrypt >= 0.2.1 module if that
is not yet updated you can install it with:

```
nimble install https://github.com/oderwat/bcryptnim.git@#fix-osx
```

You may also need to change `nimforum.nimble` such that it uses 0.2.1 by
changing the dependencies slightly.

```
[Deps]
Requires: "nim >= 0.14.0, jester#head, bcrypt >= 0.2.1, recaptcha >= 1.0.0"
```

# Running the forum

**Important: You need to compile and run `createdb` to generate the initial database
before you can run `forum` the first time**!

**Note: If you do not have a mail server set up locally, you can specify
``-d:dev`` during compilation to prevent nimforum from attempting to send
emails and to automatically activate user accounts**

This is as simple as:

```
nim c -r createdb
```

After that you can just run `forum` and if everything is ok you will get the info which URL you need to open in your browser (http://localhost:5000) to access it.

_There is an update helper `editdb` which you can safely ignore for now._

_The file `cache.nim` is included by `forum.nim` and do
not need to be compiled by you._

# Copyright

Copyright (c) 2012-2017 Andreas Rumpf, Dominik Picheta.

All rights reserved.

# License

Nimforum is licensed under the MIT license.
