import strformat, times, options, json, httpcore, sugar

import category

type
  User* = object
    name*: string
    avatarUrl*: string
    isOnline*: bool

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
  import karax / [vstyles, kajax, kdom]

  import karaxutils, error

  type
    State = ref object
      list: Option[ThreadList]
      loading: bool
      status: HttpCode

  proc newState(): State =
    State(
      list: none[ThreadList](),
      loading: false,
      status: Http200
    )

  var
    state = newState()

  proc genTopButtons(): VNode =
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

  proc render*(user: User, class: string): VNode =
    result = buildHtml():
      figure(class=class):
        img(src=user.avatarUrl, title=user.name)
        if user.isOnline:
          italic(class="avatar-presense online")

  proc renderUserMention*(user: User): VNode =
    result = buildHtml():
      # TODO: Add URL to profile.
      span(class="user-mention"):
           text "@" & user.name

  proc genUserAvatars(users: seq[User]): VNode =
    result = buildHtml(td):
      for user in users:
        render(user, "avatar avatar-sm")
        text " "

  proc renderActivity*(activity: int64): string =
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
        td(class="thread-title"):
          if thread.isLocked:
            italic(class="fas fa-lock fa-xs")
          a(href=makeUri("/t/" & $thread.id), onClick=anchorCB): text thread.topic
        td():
          render(thread.category)
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

  proc onThreadList(httpStatus: int, response: kstring) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let list = to(parsed, ThreadList)

    if state.list.isSome:
      state.list.get().threads.add(list.threads)
      state.list.get().moreCount = list.moreCount
      state.list.get().lastVisit = list.lastVisit
    else:
      state.list = some(list)

  proc onLoadMore(ev: Event, n: VNode) =
    state.loading = true
    let start = state.list.get().threads.len
    ajaxGet(makeUri("threads.json?start=" & $start), @[], onThreadList)

  proc genThreadList(): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve threads.")

    if state.list.isNone:
      ajaxGet(makeUri("threads.json"), @[], onThreadList)

      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get()
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
                i+1 < list.threads.len and
                list.threads[i].activity < list.lastVisit
              let isNew = thread.creation < list.lastVisit
              genThread(thread, isNew,
                        noBorder=isLastVisit or i+1 == list.threads.len)
              if isLastVisit:
                tr(class="last-visit-separator"):
                  td(colspan="6"):
                    span(text "last visit")

            if list.moreCount > 0:
              tr(class="load-more-separator"):
                if state.loading:
                  td(colspan="6"):
                    tdiv(class="loading loading-lg")
                else:
                  td(colspan="6", onClick=onLoadMore):
                    span(text "load more threads")

  proc renderThreadList*(): VNode =
    result = buildHtml(tdiv):
      genTopButtons()
      genThreadList()