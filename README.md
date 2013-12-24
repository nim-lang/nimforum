nimforum
========

This is Nimrod's forum. The code depends on the RST parser of the Nimrod
compiler and on Jester. The code generating captchas for registration uses the
[cairo module](http://nimrod-lang.org/cairo.html), which requires you to have
the [cairo library](http://cairographics.org) installed when you run the forum,
or you will be greeted by a cryptic error message similar to:

	$ ./forum could not load: libcairo.so(1.2)

If you are using macosx and have installed the ``cairo`` library through
[MacPorts](https://www.macports.org) you still need to add the library path to
your ``LD_LIBRARY_PATH`` environment variable. Example:

	$ LD_LIBRARY_PATH=/opt/local/lib/ ./forum

Replace ``/opt/local/lib`` with the correct path on your system.

# Copyright

Copyright (c) 2012-2013 Andreas Rumpf, Dominik Picheta.

All rights reserved.

# License

Nimforum is licensed under the MIT license.
