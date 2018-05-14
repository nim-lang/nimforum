import options
import threadlist, post
type
  Profile* = object
    user*: User
    joinTime*: int64
    threads*: seq[Thread]
    posts*: seq[Post]
    # Information that only admins should see.
    email*: Option[string]

