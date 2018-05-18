Full-text search for Nim forum
==============================

Syntax (using *SQLite* dll compiled without *Enhanced Query Syntax* support):
-----------------------------------------------------------------------------

- Only alphanumeric characters are searched.
- Only full words and words beginnings (e.g. ``Nim*`` for both ``Nimrod`` and ``Nim``) are searched
- All words are joined with implicit **AND** operator; there's no explicit one
- There's explicit **OR** operator (upper-case) and it has higher priority
- Words can be prepended with **-** to be excluded from search
- No parentheses support
- Quotes for phrases search, e.g. ``"programming language"``
- Distances between words/phrases can be specified putting ``NEAR`` or ``NEAR/some_number`` between them

Syntax - differences in *Enhanced Query Syntax* (should be enabled in *SQLite* dll):
------------------------------------------------------------------------------------

- **AND** and **NOT** logical operators available
- Precedence of operators is, from highest to lowest: **NOT**, **AND**, **OR**
- Parentheses for grouping are supported

Where search is performed:
--------------------------

- **Threads' titles** - these results are outputed first
- **Posts' titles** - middle precedence
- **Posts' contents** - the latest

How results are shown:
----------------------

- All results are ordered by date (posts' edits don't affect)
- Matched tokens in text are marked (bold or dotted underline)
- Threads title is the link to the thread and posts title is the link to the post
