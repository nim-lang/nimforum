import strformat

import threadlist


type
  PostInfo* = object
    creation*: int64
    content*: string

  Post* = object
    id*: int
    author*: User
    likes*: seq[User] ## Users that liked this post.
    seen*: bool ## Determines whether the current user saw this post.
                ## I considered using a simple timestamp for each thread,
                ## but that wouldn't work when a user navigates to the last
                ## post in a thread for example.
    history*: seq[PostInfo] ## If the post was edited this will contain the
                            ## older versions of the post.
    info*: PostInfo


when defined(js):
  import karaxutils
  proc renderPostUrl*(post: Post, thread: Thread): string =
    makeUri(fmt"/t/{thread.id}#{post.id}")