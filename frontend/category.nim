
type
  Category* = object
    id*: string
    color*: string


when defined(js):
  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils

  proc render*(category: Category): VNode =
    result = buildHtml():
      if category.id.len > 0:
        tdiv(class="triangle",
             style=style(
               (StyleAttr.borderBottom, kstring"0.6rem solid " & category.color)
        )):
          text category.id
      else:
        span()