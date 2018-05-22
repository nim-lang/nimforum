import times

type
  Rank* {.pure.} = enum ## serialized as 'status'
    Spammer          ## spammer: every post is invisible
    Troll            ## troll: cannot write new posts
    Banned           ## A non-specific ban
    Moderated        ## new member: posts manually reviewed before everybody
                     ## can see them
    EmailUnconfirmed ## member with unconfirmed email address. Their posts
                     ## are visible, but cannot make new posts. This is so that
                     ## when a user with existing posts changes their email,
                     ## their posts don't disappear.
    User             ## Ordinary user
    Moderator        ## Moderator: can change a user's rank
    Admin            ## Admin: can do everything

  User* = object
    name*: string
    avatarUrl*: string
    lastOnline*: int64
    previousVisitAt*: int64 ## Tracks the "last visit" line position
    rank*: Rank
    isDeleted*: bool

proc isOnline*(user: User): bool =
  return getTime().toUnix() - user.lastOnline < (60*5)

proc `==`*(u1, u2: User): bool =
  u1.name == u2.name

proc canPost*(rank: Rank): bool =
  ## Determines whether the specified rank can make new posts.
  rank >= Rank.User or rank == Moderated

when defined(js):
  include karax/prelude
  import karaxutils

  proc render*(user: User, class: string, showStatus=false): VNode =
    result = buildHtml():
      a(href=renderProfileUrl(user.name), onClick=anchorCB):
        figure(class=class):
          img(src=user.avatarUrl, title=user.name)
          if user.isOnline and showStatus:
            italic(class="avatar-presence online")

  proc renderUserMention*(user: User): VNode =
    result = buildHtml():
      a(class="user-mention",
        href=makeUri("/profile/" & user.name),
        onClick=anchorCB):
        text "@" & user.name

  proc renderUserRank*(user: User): VNode =
    result = buildHtml():
      case user.rank
      of Spammer, Troll, Banned:
        italic(class="fas fa-eye-ban",
               title="User is banned")
      of Rank.User, EmailUnconfirmed:
        span()
      of Moderated:
        italic(class="fas fa-eye-slash",
               title="User is moderated")
      of Moderator:
        italic(class="fas fa-shield-alt",
               title="User is a moderator")
      of Admin:
        italic(class="fas fa-chess-knight",
               title="User is an admin")