import strformat, times, options, json, httpcore, sugar

import category, user

type
  Thread* = object
    id*: int
    topic*: string
    category*: Category
    author*: User
    users*: seq[User]
    replies*: int
    views*: int
    activity*: int64 ## Unix timestamp
    creation*: int64 ## Unix timestamp
    isLocked*: bool
    isSolved*: bool

  ThreadList* = ref object
    threads*: seq[Thread]
    moreCount*: int ## How many more threads are left

proc isModerated*(thread: Thread): bool =
  ## Determines whether the specified thread is under moderation.
  ## (i.e. whether the specified thread is invisible to ordinary users).
  thread.author.rank <= Moderated

when defined(js):
  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, error, user, mainbuttons

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

  proc visibleTo*[T](thread: T, user: Option[User]): bool =
    ## Determines whether the specified thread (or post) should be
    ## shown to the user. This procedure is generic and works on any
    ## object with a `isModerated` proc.
    ##
    ## The rules for this are determined by the rank of the user, their
    ## settings (TODO), and whether the thread's creator is moderated or not.
    ##
    ## The ``user`` argument refers to the currently logged in user.
    mixin isModerated
    if user.isNone(): return not thread.isModerated

    let rank = user.get().rank
    if rank < Rank.Moderator and thread.isModerated:
      return thread.author == user.get()

    return true

  proc genUserAvatars(users: seq[User]): VNode =
    result = buildHtml(td):
      for user in users:
        render(user, "avatar avatar-sm", showStatus=true)
        text " "

  proc renderActivity*(activity: int64): string =
    let currentTime = getTime()
    let activityTime = fromUnix(activity)
    let duration = currentTime - activityTime
    if currentTime.local().year != activityTime.local().year:
      return activityTime.local().format("MMM yyyy")
    elif duration.inDays > 30 and duration.inDays < 300:
      return activityTime.local().format("MMM dd")
    elif duration.inDays != 0:
      return $duration.inDays & "d"
    elif duration.inHours != 0:
      return $duration.inHours & "h"
    elif duration.inMinutes != 0:
      return $duration.inMinutes & "m"
    else:
      return $duration.inSeconds & "s"

  proc genThread(thread: Thread, isNew: bool, noBorder: bool, displayCategory=true): VNode =
    let isOld = (getTime() - thread.creation.fromUnix).inWeeks > 2
    let isBanned = thread.author.rank.isBanned()
    result = buildHtml():
      tr(class=class({"no-border": noBorder, "banned": isBanned})):
        td(class="thread-title"):
          if thread.isLocked:
            italic(class="fas fa-lock fa-xs",
                   title="Thread cannot be replied to")
          if isBanned:
            italic(class="fas fa-ban fa-xs",
                   title="Thread author is banned")
          if thread.isModerated:
            italic(class="fas fa-eye-slash fa-xs",
                   title="Thread is moderated")
          if thread.isSolved:
            italic(class="fas fa-check-square fa-xs",
                   title="Thread has a solution")
          a(href=makeUri("/t/" & $thread.id),
            onClick=anchorCB):
            text thread.topic
        if displayCategory:
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

        let friendlyCreation = thread.creation.fromUnix.local.format(
          "'First post:' MMM d, yyyy HH:mm'\n'"
        )
        let friendlyActivity = thread.activity.fromUnix.local.format(
          "'Last reply:' MMM d, yyyy HH:mm"
        )
        td(class=class({"is-new": isNew, "is-old": isOld}, "thread-time"),
           title=friendlyCreation & friendlyActivity):
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
    else:
      state.list = some(list)

  proc onLoadMore(ev: Event, n: VNode, categoryId: int) =
    state.loading = true
    let start = state.list.get().threads.len
    ajaxGet(makeUri("threads.json?start=" & $start & "&categoryId=" & $categoryId), @[], onThreadList)

  proc getInfo(
    list: seq[Thread], i: int, currentUser: Option[User]
  ): tuple[isLastUnseen, isNew: bool] =
    ## Determines two properties about a thread.
    ##
    ## * isLastUnseen - Whether this is the last thread that had new
    ## activity since the last time the user visited the forum.
    ## * isNew - Whether this thread was created during the time that the
    #            user was absent from the forum.
    let previousVisitAt =
      if currentUser.isSome(): currentUser.get().previousVisitAt
      else: getTime().toUnix
    assert previousVisitAt != 0

    let thread = list[i]
    let isUnseen = thread.activity > previousVisitAt
    let isNextUnseen = i+1 < list.len and list[i+1].activity > previousVisitAt

    return (
      isLastUnseen: isUnseen and (not isNextUnseen),
      isNew: thread.creation > previousVisitAt
    )

  proc genThreadList(currentUser: Option[User], categoryId: int): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve threads.", state.status)

    if state.list.isNone:
      if not state.loading:
        state.loading = true
        ajaxGet(makeUri("threads.json?categoryId=" & $categoryId), @[], onThreadList)

      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get()
    result = buildHtml():
      section(class="thread-list"):
        table(class="table", id="threads-list"):
          thead():
            tr:
              th(text "Topic")
              if categoryId == -1:
                th(text "Category")
              th(style=style((StyleAttr.width, kstring"8rem"))): text "Users"
              th(text "Replies")
              th(text "Views")
              th(text "Activity")
          tbody():
            for i in 0 ..< list.threads.len:
              let thread = list.threads[i]
              if not visibleTo(thread, currentUser): continue

              let isLastThread = i+1 == list.threads.len
              let (isLastUnseen, isNew) = getInfo(list.threads, i, currentUser)
              genThread(thread, isNew,
                        noBorder=isLastUnseen or isLastThread,
                        displayCategory=categoryId == -1)
              if isLastUnseen and (not isLastThread):
                tr(class="last-visit-separator"):
                  td(colspan="6"):
                    span(text "last visit")

            if list.moreCount > 0:
              tr(class="load-more-separator"):
                if state.loading:
                  td(colspan="6"):
                    tdiv(class="loading loading-lg")
                else:
                  td(colspan="6",
                     onClick = (ev: Event, n: VNode) => (onLoadMore(ev, n, categoryId))):
                    span(text "load more threads")

  proc renderThreadList*(currentUser: Option[User], categoryId = -1): VNode =
    result = buildHtml(tdiv):
      renderMainButtons(currentUser, categoryId=categoryId)
      genThreadList(currentUser, categoryId)
