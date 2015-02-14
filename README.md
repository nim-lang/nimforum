# nimforum

This is Nim's forum. Available at http://forum.nim-lang.org.

## Building

You can use ``nimble`` (available [here](https://github.com/nim-lang/nimble) 
to get all the necessary
[dependencies](https://github.com/nim-lang/nimforum/blob/master/nimforum.nimble#L11).

Clone this repo and execute ``nimble build`` in this repositories directory.

## Dependencies

The code depends on the RST parser of the Nim
compiler and on Jester. The code generating captchas for registration uses the
[cairo module](https://github.com/nim-lang/cairo), which requires you to have
the [cairo library](http://cairographics.org) installed when you run the forum,
or you will be greeted by a cryptic error message similar to:

	$ ./forum could not load: libcairo.so(1.2)

If you are using macosx and have installed the ``cairo`` library through
[MacPorts](https://www.macports.org) you still need to add the library path to
your ``LD_LIBRARY_PATH`` environment variable. Example:

	$ LD_LIBRARY_PATH=/opt/local/lib/ ./forum

Replace ``/opt/local/lib`` with the correct path on your system.

# Copyright

Copyright (c) 2012-2015 Andreas Rumpf, Dominik Picheta.

All rights reserved.

# License

Nimforum is licensed under the MIT license.
