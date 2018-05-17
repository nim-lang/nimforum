
type
  Category* = object
    id*: int
    name*: string
    description*: string
    color*: string


when defined(js):
  include karax/prelude
  import karax / [vstyles, kajax, kdom]

  import karaxutils

  proc render*(category: Category): VNode =
    result = buildHtml():
      if category.name.len >= 0:
        tdiv(class="category",
             "data-color"="#" & category.color):
          tdiv(class="triangle",
               style=style(
                 (StyleAttr.borderBottom,
                  kstring"0.6rem solid #" & category.color)
          ))
          text category.name
      else:
        span()