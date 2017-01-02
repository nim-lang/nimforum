#
#
#              The Nim Forum
#        (c) Copyright 2012 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#

import cairo, os, strutils, jester

proc getCaptchaFilename*(i: int): string {.inline.} =
  result = "public/captchas/capture_" & $i & ".png"

proc getCaptchaUrl*(req: Request, i: int): string =
  result = req.makeUri("/captchas/capture_" & $i & ".png", absolute = false)

proc createCaptcha*(file, text: string) =
  var surface = imageSurfaceCreate(FORMAT_ARGB32, int32(10*text.len), int32(10))
  var cr = create(surface)

  selectFontFace(cr, "serif", FONT_SLANT_NORMAL, FONT_WEIGHT_BOLD)
  setFontSize(cr, 12.0)

  setSourceRgb(cr, 1.0, 0.5, 0.0)
  moveTo(cr, 0.0, 10.0)
  showText(cr, repeat('O', text.len))

  setSourceRgb(cr, 0.0, 0.0, 1.0)
  moveTo(cr, 0.0, 10.0)
  showText(cr, text)

  destroy(cr)
  discard writeToPng(surface, file)
  destroy(surface)

when isMainModule:
  createCaptcha("test.png", "1+33")
