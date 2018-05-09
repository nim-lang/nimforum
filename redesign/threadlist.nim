import strformat, times

type
  User* = object
    name*: string
    avatarUrl*: string
    isOnline*: bool

  Category* = object
    id*: string
    color*: string

  Thread* = object
    id*: int
    topic*: string
    category*: Category
    users*: seq[User]
    replies*: int
    views*: int
    activity*: int64 ## Unix timestamp
    creation*: int64 ## Unix timestamp
    isLocked*: bool
    isSolved*: bool

  ThreadList* = ref object
    threads*: seq[Thread]
    lastVisit*: int64 ## Unix timestamp
    moreCount*: int ## How many more threads are left

when defined(js):
  include karax/prelude
  import karax / [vstyles]

  import karaxutils

  proc genTopButtons*(): VNode =
    result = buildHtml():
      section(class="navbar container grid-xl", id="main-buttons"):
        section(class="navbar-section"):
          tdiv(class="dropdown"):
            a(href="#", class="btn dropdown-toggle"):
              text "Filter "
              italic(class="fas fa-caret-down")
            ul(class="menu"):
              li: text "community"
              li: text "dev"
          button(class="btn btn-primary"): text "Latest"
          button(class="btn btn-link"): text "Most Active"
          button(class="btn btn-link"): text "Categories"
        section(class="navbar-section")

  proc genUserAvatars(users: seq[User]): VNode =
    result = buildHtml(td):
      for user in users:
        figure(class="avatar avatar-sm"):
          img(src=user.avatarUrl, title=user.name)
          if user.isOnline:
            italic(class="avatar-presense online")
        text " "

  proc renderActivity(activity: int64): string =
    let currentTime = getTime()
    let activityTime = fromUnix(activity)
    let duration = currentTime - activityTime
    if duration.days > 300:
      return activityTime.local().format("MMM yyyy")
    elif duration.days > 30 and duration.days < 300:
      return activityTime.local().format("MMM dd")
    elif duration.days != 0:
      return $duration.days & "d"
    elif duration.hours != 0:
      return $duration.hours & "h"
    elif duration.minutes != 0:
      return $duration.minutes & "m"
    else:
      return $duration.seconds & "s"

  proc genThread(thread: Thread, isNew: bool, noBorder: bool): VNode =
    result = buildHtml():
      tr(class=class({"no-border": noBorder})):
        td():
          if thread.isLocked:
            italic(class="fas fa-lock fa-xs")
          text thread.topic
        td():
          if thread.category.id.len > 0:
            tdiv(class="triangle",
                 style=style(
                   (StyleAttr.borderBottom, kstring"0.6rem solid " & thread.category.color)
            )):
              text thread.category.id
        genUserAvatars(thread.users)
        td(): text $thread.replies
        td(class=class({
            "views-text": thread.views < 999,
            "popular-text": thread.views > 999 and thread.views < 5000,
            "super-popular-text": thread.views > 5000
        })):
          if thread.views > 999:
            text fmt"{thread.views/1000:.1f}k"
          else:
            text $thread.views
        td(class=class({"text-success": isNew, "text-gray": not isNew})): # TODO: Colors.
          text renderActivity(thread.activity)

  proc genThreadList*(list: ThreadList): VNode =
    result = buildHtml():
      section(class="container grid-xl"): # TODO: Rename to `.thread-list`.
        table(class="table"):
          thead():
            tr:
              th(text "Topic")
              th(text "Category")
              th(style=style((StyleAttr.width, kstring"8rem"))): text "Users"
              th(text "Replies")
              th(text "Views")
              th(text "Activity")
          tbody():
            for i in 0 ..< list.threads.len:
              let thread = list.threads[i]
              let isLastVisit =
                i+1 < list.threads.len and list.threads[i].activity < list.lastVisit
              let isNew = thread.creation < list.lastVisit
              genThread(thread, isNew,
                        noBorder=isLastVisit or i+1 == list.threads.len)
              if isLastVisit:
                tr(class="last-visit-separator"):
                  td(colspan="6"):
                    span(text "last visit")

            if list.moreCount > 0:
              tr(class="load-more-separator"):
                td(colspan="6"):
                  span(text "load more threads")
