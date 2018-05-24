Markdown and RST supported by this forum
========================================

This is a cheat sheet for the *reStructuredText* dialect as implemented by
Nim's documentation generator which has been reused for this forum.

See also the
`official RST cheat sheet <http://docutils.sourceforge.net/docs/user/rst/cheatsheet.txt>`_ 
or the `quick reference <http://docutils.sourceforge.net/docs/user/rst/quickref.html>`_
for further information.

Elements of **markdown** are also supported.

Inline elements
---------------

Ordinary text may contain *inline elements*:

===============================   ============================================
Plain text                        Result
===============================   ============================================
``*italic text*``                 *italic text*
``**bold text**``                 **bold text**
``***italic bold text***``        ***italic bold text***
\``verbatim text \``              ``verbatim text``
``http://docutils.sf.net/``       http://docutils.sf.net/
``\\escape``                      \\escape
===============================   ============================================

Quoting other users can be done by prefixing their message with ``>``::

  > Hello World

  Hi!

Which will result in:

> Hello World

Hi!

Links
-----

Links are either direct URLs like ``https://nim-lang.org`` or written like
this::
  
  `Nim <https://nim-lang.org>`_
  
Or like this::

  `<https://nim-lang.org>`_


Code blocks
-----------

The code blocks can be written in the same style as most common Markdown
flavours::

  ```nim
    if x == "abc":
      echo "xyz"
  ```

or using RST syntax::

  .. code-block:: nim
    
    if x == "abc":
      echo "xyz"

Both are rendered as:

.. code-block:: nim
  
  if x == "abc":
    echo "xyz"


Apart from Nim, the programming languages C, C++, Java and C# also
have highlighting support.

Literal blocks
--------------

These are introduced by '::' and a newline. The block is indicated by indentation:

::
  ::
    if x == "abc":
      echo "xyz"
      
The above is rendered as::

    if x == "abc":
      echo "xyz"



Bullet lists
------------

Bullet lists look like this::

  * Item 1
  * Item 2 that
    spans over multiple lines
  * Item 3
  * Item 4
    - bullet lists may nest
    - item 3b
    - valid bullet characters are ``+``, ``*`` and ``-``

The above rendered as:
* Item 1
* Item 2 that
  spans over multiple lines
* Item 3
* Item 4
  - bullet lists may nest
  - item 3b
  - valid bullet characters are ``+``, ``*`` and ``-``


Enumerated lists
----------------

Enumerated lists are written like this::

  1. This is the first item
  2. This is the second item
  3. Enumerators are arabic numbers,
     single letters, or roman numerals
  #. This item is auto-enumerated 

They are rendered as:

1. This is the first item
2. This is the second item
3. Enumerators are arabic numbers,
   single letters, or roman numerals
#. This item is auto-enumerated


Tables
------

Only *simple tables* are supported. They are of the form::

  ==================      ===============       ===================
  header 1                header 2              header n
  ==================      ===============       ===================
  Cell 1                  Cell 2                Cell 3
  Cell 4                  Cell 5; any           Cell 6
                          cell that is
                          not in column 1
                          may span over
                          multiple lines
  Cell 7                  Cell 8                Cell 9
  ==================      ===============       ===================

This results in:
==================      ===============       ===================
header 1                header 2              header n
==================      ===============       ===================
Cell 1                  Cell 2                Cell 3
Cell 4                  Cell 5; any           Cell 6
                        cell that is
                        not in column 1
                        may span over
                        multiple lines
Cell 7                  Cell 8                Cell 9
==================      ===============       ===================

Images
------

Image embedding is supported. This includes GIFs as well as mp4 (for which a
<video> tag will be automatically generated).

For example:

```
.. image:: https://upload.wikimedia.org/wikipedia/commons/6/69/Dog_morphological_variation.png
```

Will render as:

.. image:: https://upload.wikimedia.org/wikipedia/commons/6/69/Dog_morphological_variation.png

And a GIF example:

```
.. image:: https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif
```

Will render as:

.. image:: https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif

You can also specify the size of the image:

```
.. image:: https://upload.wikimedia.org/wikipedia/commons/6/69/Dog_morphological_variation.png
   :width: 40%
```

.. image:: https://upload.wikimedia.org/wikipedia/commons/6/69/Dog_morphological_variation.png
   :width: 40%