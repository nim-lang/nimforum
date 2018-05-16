import times

type
  Rank* {.pure.} = enum ## serialized as 'status'
    Spammer          ## spammer: every post is invisible
    Troll            ## troll: cannot write new posts
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
      # TODO: Add URL to profile.
      span(class="user-mention"):
           text "@" & user.name