when defined(js):
  import sugar, httpcore
  import dom except Event

  include karax/prelude
  import karax / [kajax]

  import error
  import karaxutils

  type
    About* = ref object
      loading: bool
      status: HttpCode
      content: kstring
      page: string

  proc newAbout*(): About =
    About(
      status: Http200
    )

  proc onContent(status: int, response: kstring, state: About) =
    state.status = status.HttpCode
    state.content = response

  proc render*(state: About, page: string): VNode =
    if state.status != Http200:
      return renderError($state.content, state.status)

    if page != state.page:
      if not state.loading:
        state.page = page
        state.loading = true
        state.status = Http200
        let uri = makeUri("/about/" & page & ".html")
        ajaxGet(uri, @[], (s: int, r: kstring) => onContent(s, r, state))

      return buildHtml(tdiv(class="loading"))

    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(class="about"):
          verbatim(state.content)