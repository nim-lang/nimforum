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
compiler and on Jester. The code generating captchas for registration uses the
[cairo module](https://github.com/nim-lang/cairo), which requires you to have
the [cairo library](http://cairographics.org) installed when you run the forum,
or you will be greeted by a cryptic error message similar to:

	$ ./forum could not load: libcairo.so(1.2)

### Mac OS X

#### cairo
If you are using macosx and have installed the ``cairo`` library through
[MacPorts](https://www.macports.org) you still need to add the library path to
your ``LD_LIBRARY_PATH`` environment variable. Example:

	$ LD_LIBRARY_PATH=/opt/local/lib/ ./forum

Replace ``/opt/local/lib`` with the correct path on your system.

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
Requires: "nimrod >= 0.10.3, cairo#head, jester#head, bcrypt >= 0.2.1"
```

# Running the forum

**Important: You need to compile and run `createdb` to generate the initial database
before you can run `forum` the first time**!

This is as simple as:

```
nim c -r createdb
```

After that you can just run `forum` and if everything is ok you will get the info which URL you need to open in your browser (http://localhost:5000) to access it.

_There is an update helper `editdb` which you can safely ignore for now._

_The files `captchas.nim`, `cache.nim` are included by `forum.nim` and do
not need to be compiled by you._

# Copyright

Copyright (c) 2012-2015 Andreas Rumpf, Dominik Picheta.

All rights reserved.

# License

Nimforum is licensed under the MIT license.
