reStructuredText cheat sheet
===========================================================================

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

Links
-----

Links are either direct URLs like ``https://nim-lang.org`` or written like
this::
  
  `Nim <https://nim-lang.org>`_
  
Or like this::

  `<https://nim-lang.org>`_


Code blocks
-----------

are done this way::

  .. code-block:: nim
    
    if x == "abc":
      echo "xyz"


Is rendered as:

.. code-block:: nim
  
  if x == "abc":
    echo "xyz"


Except Nim, the programming languages C, C++, Java and C# have highlighting
support.

An alternative github-like syntax is also supported. This has the advantage
that no excessive indentation is needed::

  ```nim  
    if x == "abc":
      echo "xyz"```

Is rendered as:

.. code-block:: nim
  
  if x == "abc":
    echo "xyz"



Literal blocks
--------------

Are introduced by '::' and a newline. The block is indicated by indentation: 

::
  ::
    if x == "abc":
      echo "xyz"
      
Is rendered as::

    if x == "abc":
      echo "xyz"



Bullet lists
------------

look like this::

  * Item 1
  * Item 2 that
    spans over multiple lines
  * Item 3
  * Item 4
    - bullet lists may nest
    - item 3b
    - valid bullet characters are ``+``, ``*`` and ``-``

Is rendered as:
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

are written like this::

  1. This is the first item
  2. This is the second item
  3. Enumerators are arabic numbers,
     single letters, or roman numerals
  #. This item is auto-enumerated 

Is rendered as:

1. This is the first item
2. This is the second item
3. Enumerators are arabic numbers,
   single letters, or roman numerals
#. This item is auto-enumerated 


Quoting someone
---------------

quotes are just::

    **Someone said**:  Indented paragraphs,

        and they may nest. 

Is rendered as:

    **Someone said**:  Indented paragraphs,

        and they may nest. 



Definition lists
----------------

are written like this::

  what
    Definition lists associate a term with
    a definition.

  how
    The term is a one-line phrase, and the
    definition is one or more paragraphs or
    body elements, indented relative to the
    term. Blank lines are not allowed
    between term and definition.

and look like:

what
  Definition lists associate a term with
  a definition.

how
  The term is a one-line phrase, and the
  definition is one or more paragraphs or
  body elements, indented relative to the
  term. Blank lines are not allowed
  between term and definition.


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

```
.. image:: path/to/img.png
```