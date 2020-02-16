when defined(js):
  import sugar, httpcore, options, json
  import dom except Event

  include karax/prelude
  import karax / [kajax, kdom]

  import error
  import karaxutils

  type
    ActivateEmail* = ref object
      loading: bool
      status: HttpCode
      error: Option[PostError]

  proc newActivateEmail*(): ActivateEmail =
    ActivateEmail(
      status: Http200
    )

  proc onPost(httpStatus: int, response: kstring, state: ActivateEmail) =
    postFinished:
      navigateTo(makeUri("/activateEmail/success"))

  proc onSetClick(
    ev: Event, n: VNode,
    state: ActivateEmail
  ) =
    state.loading = true
    state.error = none[PostError]()

    let uri = makeUri("activateEmail", search = $kdom.window.location.search)
    ajaxPost(uri, @[], "",
             (s: int, r: kstring) => onPost(s, r, state))

  proc render*(state: ActivateEmail): VNode =
    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(id="activateemail"):
          tdiv(class="title"):
            p(): text "Activate Email"
          tdiv(class="content"):
            button(class=class(
                    {"loading": state.loading},
                    "btn btn-primary"
                   ),
                   onClick=(ev: Event, n: VNode) =>
                    (onSetClick(ev, n, state))):
              text "Activate"
            if state.error.isSome():
              p(class="text-error"):
                text state.error.get().message