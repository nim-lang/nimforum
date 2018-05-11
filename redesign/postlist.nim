
import options, json, times, httpcore, strformat, sugar, math

import threadlist, category
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

  PostList* = ref object
    thread*: Thread
    history*: seq[Thread] ## If the thread was edited this will contain the
                          ## older versions of the thread (title/category
                          ## changes).
    posts*: seq[Post]
    moreCount*: int

when defined(js):
  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, error

  type
    State = ref object
      list: Option[PostList]
      loading: bool
      status: HttpCode
      replyBoxShown: bool

  proc newState(): State =
    State(
      list: none[PostList](),
      loading: false,
      status: Http200
    )

  var
    state = newState()

  proc onPostList(httpStatus: int, response: kstring, start: int) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let list = to(parsed, PostList)

    if state.list.isSome and state.list.get().thread.id == list.thread.id:
      var old = state.list.get()
      for i in 0..<list.posts.len:
        old.posts.insert(list.posts[i], i+start)

      state.list = some(list)
      state.list.get().posts = old.posts
    else:
      state.list = some(list)

  proc renderPostUrl(post: Post, thread: Thread): string =
    makeUri(fmt"/t/{thread.id}/p/{post.id}")

  proc genPost(post: Post, thread: Thread, isLoggedIn: bool): VNode =
    result = buildHtml():
      tdiv(class="post"):
        tdiv(class="post-icon"):
          render(post.author, "post-avatar")
        tdiv(class="post-main"):
          tdiv(class="post-title"):
            tdiv(class="post-username"):
              text post.author.name
            tdiv(class="post-time"):
              let title = post.info.creation.fromUnix().local.
                          format("MMM d, yyyy HH:mm")
              a(href=renderPostUrl(post, thread), title=title):
                text renderActivity(post.info.creation)
          tdiv(class="post-content"):
            p(text post.info.content) # TODO: RSTGEN
          tdiv(class="post-buttons"):
            tdiv(class="like-button"):
              button(class="btn"):
                span(class="like-count"):
                  if post.likes.len > 0:
                    text $post.likes.len
                  italic(class="far fa-heart")
            if isLoggedIn:
              tdiv(class="flag-button"):
                button(class="btn"):
                  italic(class="far fa-flag")
              tdiv(class="reply-button"):
                button(class="btn"):
                  italic(class="fas fa-reply")
                  text " Reply"

  proc onLoadMore(ev: Event, n: VNode) =
    if state.loading: return

    state.loading = true
    let start = n.getAttr("data-start").parseInt()
    let threadId = state.list.get().thread.id
    let uri = makeUri("posts.json", [("start", $start), ("id", $threadId)])
    ajaxGet(uri, @[], (s: int, r: kstring) => onPostList(s, r, start))

  proc genLoadMore(start: int): VNode =
    result = buildHtml():
      tdiv(class="information load-more-posts",
           onClick=onLoadMore,
           "data-start" = $start):
        tdiv(class="information-icon"):
          italic(class="fas fa-comment-dots")
        tdiv(class="information-main"):
          if state.loading:
            tdiv(class="loading loading-lg")
          else:
            tdiv(class="information-title"):
              text "Load more posts "
              span(class="more-post-count"):
                text "(" & $state.list.get().moreCount & ")"

  proc genTimePassed(prevPost: Post, post: Option[Post]): VNode =
    var latestTime =
      if post.isSome: post.get().info.creation.fromUnix()
      else: getTime()

    # TODO: Use `between` once it's merged into stdlib.
    var diffStr = "Some time later"
    let diff = latestTime - prevPost.info.creation.fromUnix()
    if diff.weeks > 48:
      let years = diff.weeks div 48
      diffStr = $years & " years later"
    elif diff.weeks > 4:
      let months = diff.weeks div 4
      diffStr = $months & " months later"
    else:
      return buildHtml(tdiv())

    # PROTIP: Good thread ID to test this with is: 1267.
    result = buildHtml():
      tdiv(class="information time-passed"):
        tdiv(class="information-icon"):
          italic(class="fas fa-clock")
        tdiv(class="information-main"):
          tdiv(class="information-title"):
            text diffStr


  proc renderPostList*(threadId: int, isLoggedIn: bool): VNode =
    if state.status != Http200:
      return renderError("Couldn't retrieve posts.")

    if state.list.isNone or state.list.get().thread.id != threadId:
      let uri = makeUri("posts.json", ("id", $threadId))
      ajaxGet(uri, @[], (s: int, r: kstring) => onPostList(s, r, 0))

      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get()
    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(class="title"):
          p(): text list.thread.topic
          render(list.thread.category)
        tdiv(class="posts"):
          var prevPost: Option[Post] = none[Post]()
          for post in list.posts:
            if prevPost.isSome:
              genTimePassed(prevPost.get(), some(post))
            genPost(post, list.thread, isLoggedIn)
            prevPost = some(post)

          if state.replyBoxShown and prevPost.isSome:
            genTimePassed(prevPost.get(), none[Post]())

          if list.moreCount > 0:
            genLoadMore(list.posts.len)
