Full-text search for Nim forum
==============================

- Only alphanumeric characters are searched.
- Only full words and words beginnings (e.g. ``Nim*`` for both ``Nimrod`` and ``Nim``) are searched
- All words are joined with implicit **AND** operator; there's no explicit one
- There's explicit **OR** operator (upper-case) and it has higher priority
- Words can be prepended with **-** to be excluded from search
- No parentheses support
- Quotes for phrases search, e.g. ``"programming language"``
- Distances between words/phrases can be specified putting ``NEAR`` or ``NEAR/some_number`` between them

Where search is performed:
--------------------------

- **Threads' titles**
- **Posts' contents**
- **User names**

How results are shown:
----------------------

- All results are ordered by date (posts' edits don't affect)
- Matched tokens in text are marked (bold or underline)
- Posts title is the link to the post

Username search:
-----------------

The first and the last words of the search are checked to being a username of an existing user. If so, then additionally posts/threads of that user are searched with the query without the username.

E.g.: Considering there exists a user *User1*, *"User1 macro"* searches for *User1*'s posts containing word *"macro"* and any user's posts containing simultaneously both words *"User1"* and *"macro"*.

To search for all threads and posts of some user, enter just username.
