import times

type
  Rank* {.pure.} = enum ## serialized as 'status'
    Spammer          ## spammer: every post is invisible
    Troll            ## troll: cannot write new posts
    Banned           ## A non-specific ban
    EmailUnconfirmed ## member with unconfirmed email address
    Moderated        ## new member: posts manually reviewed before everybody
                     ## can see them
    User             ## Ordinary user
    Moderator        ## Moderator: can change a user's rank
    Admin            ## Admin: can do everything

  User* = object
    name*: string
    avatarUrl*: string
    lastOnline*: int64
    rank*: Rank

proc isOnline*(user: User): bool =
  return getTime().toUnix() - user.lastOnline < (60*5)

proc `==`*(u1, u2: User): bool =
  u1.name == u2.name

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