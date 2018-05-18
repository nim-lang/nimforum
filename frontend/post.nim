import strformat, options

import user, threadlist

type
  PostInfo* = object
    creation*: int64
    content*: string

  Post* = ref object
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
    moreBefore*: seq[int]
    replyingTo*: Option[PostLink]

  PostLink* = object ## Used by profile
    creation*: int64
    topic*: string
    threadId*: int
    postId*: int
    author*: Option[User] ## Only used for `replyingTo`.

proc lastEdit*(post: Post): PostInfo =
  post.history[^1]

proc isModerated*(post: Post): bool =
  ## Determines whether the specified thread is under moderation.
  post.author.rank <= Moderated

proc isLikedBy*(post: Post, user: Option[User]): bool =
  ## Determines whether the specified user has liked the post.
  if user.isNone(): return false

  for u in post.likes:
    if u.name == user.get().name:
      return true

  return false

when defined(js):
  import karaxutils

  proc renderPostUrl*(post: Post, thread: Thread): string =
    renderPostUrl(thread.id, post.id)

  proc renderPostUrl*(link: PostLink): string =
    renderPostUrl(link.threadId, link.postId)