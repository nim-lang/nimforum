
import system except Thread
import options, json, times, httpcore, strformat, sugar, math, strutils
import sequtils

import threadlist, category, post, user
type

  PostList* = ref object
    thread*: Thread
    history*: seq[Thread] ## If the thread was edited this will contain the
                          ## older versions of the thread (title/category
                          ## changes).
    posts*: seq[Post]

when defined(js):
  from dom import nil

  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, error, replybox, editbox, postbutton, delete

  type
    State = ref object
      list: Option[PostList]
      loading: bool
      status: HttpCode
      replyingTo: Option[Post]
      replyBox: ReplyBox
      editing: Option[Post] ## If in edit mode, this contains the post.
      editBox: EditBox
      likeButton: LikeButton
      deleteModal: DeleteModal

  proc onReplyPosted(id: int)
  proc onEditPosted(id: int, content: string, subject: Option[string])
  proc onEditCancelled()
  proc onDeletePost(post: Post)
  proc onDeleteThread(thread: Thread)
  proc newState(): State =
    State(
      list: none[PostList](),
      loading: false,
      status: Http200,
      replyingTo: none[Post](),
      replyBox: newReplyBox(onReplyPosted),
      editBox: newEditBox(onEditPosted, onEditCancelled),
      likeButton: newLikeButton(),
      deleteModal: newDeleteModal(onDeletePost, onDeleteThread, nil)
    )

  var
    state = newState()

  proc onPostList(httpStatus: int, response: kstring, postId: Option[int]) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let list = to(parsed, PostList)

    state.list = some(list)

    # The anchor should be jumped to once all the posts have been loaded.
    if postId.isSome():
      discard setTimeout(
        () => (
          # Would have used scrollIntoView but then the `:target` selector
          # isn't activated.
          window.location.hash = "";
          window.location.hash = "#" & $postId.get()
        ),
        100
      )

  proc onMorePosts(httpStatus: int, response: kstring, start: int) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    var list = to(parsed, seq[Post])

    var idsLoaded: seq[int] = @[]
    for i in 0..<list.len:
      state.list.get().posts.insert(list[i], i+start)
      idsLoaded.add(list[i].id)

    # Save a list of the IDs which have not yet been loaded into the top-most
    # post.
    let postIndex = start+list.len
    # The following check is necessary because we reuse this proc to load
    # a newly created post.
    if postIndex < state.list.get().posts.len:
      let post = state.list.get().posts[postIndex]
      var newPostIds: seq[int] = @[]
      for id in post.moreBefore:
        if id notin idsLoaded:
          newPostIds.add(id)
      post.moreBefore = newPostIds

  proc loadMore(start: int, ids: seq[int]) =
    if state.loading: return

    state.loading = true
    let uri = makeUri(
      "specific_posts.json",
      [("ids", $(%ids))]
    )
    ajaxGet(
      uri,
      @[],
      (s: int, r: kstring) => onMorePosts(s, r, start)
    )

  proc onReplyPosted(id: int) =
    ## Executed when a reply has been successfully posted.
    loadMore(state.list.get().posts.len, @[id])

  proc onEditCancelled() = state.editing = none[Post]()

  proc onEditPosted(id: int, content: string, subject: Option[string]) =
    ## Executed when an edit has been successfully posted.
    state.editing = none[Post]()
    let list = state.list.get()
    for i in 0 ..< list.posts.len:
      if list.posts[i].id == id:
        list.posts[i].history.add(PostInfo(
          creation: getTime().toUnix(),
          content: content
        ))
        break

  proc onReplyClick(e: Event, n: VNode, p: Option[Post]) =
    state.replyingTo = p
    state.replyBox.show()

  proc onEditClick(e: Event, n: VNode, p: Post) =
    state.editing = some(p)

    # TODO: Ensure the edit box is as big as its content. Auto resize the
    # text area.

  proc onDeletePost(post: Post) =
    state.list.get().posts.keepIf(
      x => x.id != post.id
    )

  proc onDeleteThread(thread: Thread) =
    window.location.href = makeUri("/")

  proc onDeleteClick(e: Event, n: VNode, p: Post) =
    let list = state.list.get()
    if list.posts[0].id == p.id:
      state.deleteModal.show(list.thread)
    else:
      state.deleteModal.show(p)

  proc onLoadMore(ev: Event, n: VNode, start: int, post: Post) =
    loadMore(start, post.moreBefore) # TODO: Don't load all!

  proc genLoadMore(post: Post, start: int): VNode =
    result = buildHtml():
      tdiv(class="information load-more-posts",
           onClick=(e: Event, n: VNode) => onLoadMore(e, n, start, post)):
        tdiv(class="information-icon"):
          italic(class="fas fa-comment-dots")
        tdiv(class="information-main"):
          if state.loading:
            tdiv(class="loading loading-lg")
          else:
            tdiv(class="information-title"):
              text "Load more posts "
              span(class="more-post-count"):
                text "(" & $post.moreBefore.len & ")"

  proc genPostButtons(post: Post, currentUser: Option[User]): Vnode =
    let loggedIn = currentUser.isSome()
    let authoredByUser =
      loggedIn and currentUser.get().name == post.author.name
    let currentAdmin =
      currentUser.isSome() and currentUser.get().rank == Admin

    # Don't show buttons if the post is being edited.
    if state.editing.isSome() and state.editing.get() == post:
      return buildHtml(tdiv())

    result = buildHtml():
      tdiv(class="post-buttons"):
        if authoredByUser or currentAdmin:
          tdiv(class="edit-button", onClick=(e: Event, n: VNode) =>
               onEditClick(e, n, post)):
            button(class="btn"):
              italic(class="far fa-edit")
          tdiv(class="delete-button",
               onClick=(e: Event, n: VNode) => onDeleteClick(e, n, post)):
            button(class="btn"):
              italic(class="far fa-trash-alt")

        render(state.likeButton, post, currentUser)

        if loggedIn:
          tdiv(class="flag-button"):
            button(class="btn"):
              italic(class="far fa-flag")

          tdiv(class="reply-button"):
            button(class="btn", onClick=(e: Event, n: VNode) =>
                   onReplyClick(e, n, some(post))):
              italic(class="fas fa-reply")
              text " Reply"

  proc genPost(post: Post, thread: Thread, currentUser: Option[User]): VNode =
    let postCopy = post # TODO: Another workaround here, closure capture :(

    result = buildHtml():
      tdiv(class="post", id = $post.id):
        tdiv(class="post-icon"):
          render(post.author, "post-avatar")
        tdiv(class="post-main"):
          tdiv(class="post-title"):
            tdiv(class="post-username"):
              text post.author.name
              if post.isModerated:
                italic(class="fas fa-eye-slash",
                       title="User is moderated")
              if post.author.rank == Moderator:
                italic(class="fas fa-shield-alt",
                       title="User is a moderator")
              if post.author.rank == Admin:
                italic(class="fas fa-chess-knight",
                       title="User is an admin")
            tdiv(class="post-metadata"):
              if post.replyingTo.isSome():
                let replyingTo = post.replyingTo.get()
                tdiv(class="post-replyingTo"):
                  a(href=renderPostUrl(replyingTo)):
                    italic(class="fas fa-reply")
                  renderUserMention(replyingTo.author.get())
              if post.history.len > 0:
                let title = post.lastEdit.creation.fromUnix().local.
                            format("'Last modified' MMM d, yyyy HH:mm")
                tdiv(class="post-history", title=title):
                  span(class="edit-count"):
                    text $post.history.len
                  italic(class="fas fa-pencil-alt")

              let title = post.info.creation.fromUnix().local.
                          format("MMM d, yyyy HH:mm")
              a(href=renderPostUrl(post, thread), title=title):
                text renderActivity(post.info.creation)
          tdiv(class="post-content"):
            if state.editing.isSome() and state.editing.get() == post:
              render(state.editBox, postCopy)
            else:
              let content =
                if post.history.len > 0:
                  post.lastEdit.content
                else:
                  post.info.content
              verbatim(content)

          genPostButtons(postCopy, currentUser)

  proc genTimePassed(prevPost: Post, post: Option[Post], last: bool): VNode =
    var latestTime =
      if post.isSome: post.get().info.creation.fromUnix()
      else: getTime()

    # TODO: Use `between` once it's merged into stdlib.
    let
      tmpl =
        if last: [
            "A long time since last reply",
            "$1 year since last reply",
            "$1 years since last reply",
            "$1 month since last reply",
            "$1 months since last reply",
          ]
        else: [
          "Some time later",
          "$1 year later", "$1 years later",
          "$1 month later", "$1 months later"
        ]
    var diffStr = tmpl[0]
    let diff = latestTime - prevPost.info.creation.fromUnix()
    if diff.weeks > 48:
      let years = diff.weeks div 48
      diffStr =
        (if years == 1: tmpl[1] else: tmpl[2]) % $years
    elif diff.weeks > 4:
      let months = diff.weeks div 4
      diffStr =
        (if months == 1: tmpl[3] else: tmpl[4]) % $months
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

  proc renderPostList*(threadId: int, postId: Option[int],
                       currentUser: Option[User]): VNode =
    if state.list.isSome() and state.list.get().thread.id != threadId:
      state.list = none[PostList]()
      state.status = Http200

    if state.status != Http200:
      return renderError("Couldn't retrieve posts.", state.status)

    if state.list.isNone:
      var params = @[("id", $threadId)]
      if postId.isSome():
        params.add(("anchor", $postId.get()))
      let uri = makeUri("posts.json", params)
      ajaxGet(uri, @[], (s: int, r: kstring) => onPostList(s, r, postId))

      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get()
    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(class="title"):
          p(): text list.thread.topic
          if list.thread.isLocked:
            italic(class="fas fa-lock fa-xs",
                   title="Thread cannot be replied to")
            text "Locked"
          if list.thread.isModerated:
            italic(class="fas fa-eye-slash fa-xs",
                   title="Thread is moderated")
            text "Moderated"
          if list.thread.isSolved:
            italic(class="fas fa-check-square fa-xs",
                   title="Thread has a solution")
            text "Solved"
          render(list.thread.category)
        tdiv(class="posts"):
          var prevPost: Option[Post] = none[Post]()
          for i, post in list.posts:
            if not post.visibleTo(currentUser): continue

            if prevPost.isSome:
              genTimePassed(prevPost.get(), some(post), false)
            if post.moreBefore.len > 0:
              genLoadMore(post, i)
            genPost(post, list.thread, currentUser)
            prevPost = some(post)

          if prevPost.isSome:
            genTimePassed(prevPost.get(), none[Post](), true)

          tdiv(id="thread-buttons"):
            button(class="btn btn-secondary",
                   onClick=(e: Event, n: VNode) =>
                         onReplyClick(e, n, none[Post]())):
              italic(class="fas fa-reply")
              text " Reply"

          render(state.replyBox, list.thread, state.replyingTo, false)

          render(state.deleteModal)