## Simple generic button that can be clicked to make a post request.
## The button will show a loading indicator and a tick on success.
##
## Used for password reset emails.

import options, httpcore, json, sugar, sequtils, strutils
when defined(js):
  include karax/prelude
  import karax/[kajax, kdom]

  import error, karaxutils, post, user, threadlist

  type
    PostButton* = ref object
      uri, title, icon: string
      formData: FormData
      error: Option[PostError]
      loading: bool
      posted: bool

  proc newPostButton*(uri: string, formData: FormData,
                      title: string, icon: string): PostButton =
    PostButton(
      uri: uri,
      formData: formData,
      title: title,
      icon: icon
    )

  proc newResetPasswordButton*(username: string): PostButton =
    var formData = newFormData()
    formData.append("email", username)
    result = newPostButton(
        makeUri("/sendResetPassword"),
        formData,
        "Send password reset email",
        "fas fa-envelope",
    )

  proc onPost(httpStatus: int, response: kstring, state: PostButton) =
    postFinished:
      discard

  proc onClick(ev: Event, n: VNode, state: PostButton) =
    if state.loading or state.posted: return

    state.loading = true
    state.posted = true
    state.error = none[PostError]()

    # TODO: This is a hack, karax should support this.
    ajaxPost(state.uri, @[], cast[cstring](state.formData),
             (s: int, r: kstring) => onPost(s, r, state))

    ev.preventDefault()

  proc render*(state: PostButton, disabled: bool): VNode =
    result = buildHtml(tdiv()):
      button(class=class({
                "loading": state.loading,
                "disabled": disabled
              },
              "btn btn-secondary"
             ),
             `type`="button",
             onClick=(e: Event, n: VNode) => (onClick(e, n, state))):
        if state.posted:
          if state.error.isNone():
            italic(class="fas fa-check")
          else:
            italic(class="fas fa-times")
        else:
          italic(class=state.icon)
        text " " & state.title

      if state.error.isSome():
        p(class="text-error"):
          text state.error.get().message


  type
    LikeButton* = ref object
      error: Option[PostError]
      loading: bool

  proc newLikeButton*(): LikeButton =
    LikeButton()

  proc onPost(httpStatus: int, response: kstring, state: LikeButton,
              post: Post, user: User) =
    postFinished:
      if post.isLikedBy(some(user)):
        var newLikes: seq[User] = @[]
        for like in post.likes:
          if like.name != user.name:
            newLikes.add(like)
        post.likes = newLikes
      else:
        post.likes.add(user)

  proc onClick(ev: Event, n: VNode, state: LikeButton, post: Post,
               currentUser: Option[User]) =
    if state.loading: return
    if currentUser.isNone():
      state.error = some[PostError](PostError(message: "Not logged in."))
      return

    state.loading = true
    state.error = none[PostError]()

    # TODO: This is a hack, karax should support this.
    var formData = newFormData()
    formData.append("id", $post.id)
    let uri =
      if post.isLikedBy(currentUser):
        makeUri("/unlike")
      else:
        makeUri("/like")
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) =>
                onPost(s, r, state, post, currentUser.get()))

    ev.preventDefault()

  proc render*(state: LikeButton, post: Post,
               currentUser: Option[User]): VNode =

    let liked = isLikedBy(post, currentUser)
    let tooltip =
      if state.error.isSome(): state.error.get().message
      else: ""

    result = buildHtml():
      tdiv(class="like-button"):
        button(class=class({"tooltip": state.error.isSome()}, "btn"),
               onClick=(e: Event, n: VNode) =>
                  (onClick(e, n, state, post, currentUser)),
               "data-tooltip"=tooltip,
               onmouseleave=(e: Event, n: VNode) =>
                  (state.error = none[PostError]())):
          if post.likes.len > 0:
            let names = post.likes.map(x => x.name).join(", ")
            span(class="like-count tooltip", "data-tooltip"=names):
              text $post.likes.len

          italic(class=class({"far": not liked, "fas": liked}, "fa-heart"))

  type
    LockButton* = ref object
      error: Option[PostError]
      loading: bool

  proc newLockButton*(): LockButton =
    LockButton()

  proc onPost(httpStatus: int, response: kstring, state: LockButton,
              thread: var Thread) =
    postFinished:
      thread.isLocked = not thread.isLocked

  proc onLockClick(ev: Event, n: VNode, state: LockButton, thread: var Thread) =
    if state.loading: return

    state.loading = true
    state.error = none[PostError]()

    # TODO: This is a hack, karax should support this.
    var formData = newFormData()
    formData.append("id", $thread.id)
    let uri =
      if thread.isLocked:
        makeUri("/unlock")
      else:
        makeUri("/lock")
    ajaxPost(uri, @[], cast[cstring](formData),
             (s: int, r: kstring) =>
                onPost(s, r, state, thread))

    ev.preventDefault()

  proc render*(state: LockButton, thread: var Thread,
               currentUser: Option[User]): VNode =
    if currentUser.isNone() or
       currentUser.get().rank < Moderator:
      return buildHtml(tdiv())

    let tooltip =
      if state.error.isSome(): state.error.get().message
      else: ""

    result = buildHtml():
      button(class="btn btn-secondary",
           onClick=(e: Event, n: VNode) =>
              onLockClick(e, n, state, thread),
           "data-tooltip"=tooltip,
           onmouseleave=(e: Event, n: VNode) =>
              (state.error = none[PostError]())):
        if thread.isLocked:
          italic(class="fas fa-unlock-alt")
          text " Unlock Thread"
        else:
          italic(class="fas fa-lock")
          text " Lock Thread"