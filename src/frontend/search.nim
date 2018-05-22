
import user, options, httpcore, json, times
type
  SearchResultKind* = enum
    ThreadMatch, PostMatch

  SearchResult* = object
    kind*: SearchResultKind
    threadId*: int
    postId*: int
    threadTitle*: string
    postContent*: string
    author*: User
    creation*: int64

proc isModerated*(searchResult: SearchResult): bool =
  return searchResult.author.rank <= Moderated

when defined(js):
  from dom import nil

  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils, error, threadlist, sugar

  type
    Search* = ref object
      list: Option[seq[SearchResult]]
      loading: bool
      status: HttpCode
      query: string

  proc newSearch*(): Search =
    Search(
      list: none[seq[SearchResult]](),
      loading: false,
      status: Http200,
      query: ""
    )

  proc onList(httpStatus: int, response: kstring, state: Search) =
    state.loading = false
    state.status = httpStatus.HttpCode
    if state.status != Http200: return

    let parsed = parseJson($response)
    let list = to(parsed, seq[SearchResult])

    state.list = some(list)

  proc genSearchResult(searchResult: SearchResult): VNode =
    let url = renderPostUrl(searchResult.threadId, searchResult.postId)
    result = buildHtml():
      tdiv(class="post", id = $searchResult.postId):
        tdiv(class="post-icon"):
          render(searchResult.author, "post-avatar")
        tdiv(class="post-main"):
          tdiv(class="post-title"):
            tdiv(class="thread-title"):
              a(href=url):
                verbatim(searchResult.threadTitle)
            tdiv(class="post-username"):
              text searchResult.author.name
              renderUserRank(searchResult.author)
            tdiv(class="post-metadata"):
              # TODO: History and replying to.
              let title = searchResult.creation.fromUnix().local.
                          format("MMM d, yyyy HH:mm")
              a(href=url, title=title):
                text renderActivity(searchResult.creation)
          tdiv(class="post-content"):
            verbatim(searchResult.postContent)

  proc render*(state: Search, query: string, currentUser: Option[User]): VNode =
    if state.list.isNone() or state.query != query:
      state.list = none[seq[SearchResult]]()
      state.status = Http200
      state.query = query

    if state.status != Http200:
      return renderError("Couldn't retrieve search results.", state.status)

    if state.list.isNone:
      var params = @[("q", state.query)]
      let uri = makeUri("search.json", params)
      ajaxGet(uri, @[], (s: int, r: kstring) => onList(s, r, state))

      return buildHtml(tdiv(class="loading loading-lg"))

    let list = state.list.get()
    result = buildHtml():
      section(class="container grid-xl"):
        tdiv(class="title"):
          p(): text "Search results"
        tdiv(class="searchresults"):
          if list.len == 0:
            renderMessage("No results found", "", "fa-exclamation")
          else:
            for searchResult in list:
              if not searchResult.visibleTo(currentUser): continue
              genSearchResult(searchResult)
