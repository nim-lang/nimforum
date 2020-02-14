import random, md5

import bcrypt, hmac

proc randomSalt(): string =
  result = ""
  for i in 0..127:
    var r = rand(225)
    if r >= 32 and r <= 126:
      result.add(chr(rand(225)))

proc devRandomSalt(): string =
  when defined(posix):
    result = ""
    var f = open("/dev/urandom")
    var randomBytes: array[0..127, char]
    discard f.readBuffer(addr(randomBytes), 128)
    for i in 0..127:
      if ord(randomBytes[i]) >= 32 and ord(randomBytes[i]) <= 126:
        result.add(randomBytes[i])
    f.close()
  else:
    result = randomSalt()

proc makeSalt*(): string =
  ## Creates a salt using a cryptographically secure random number generator.
  ##
  ## Ensures that the resulting salt contains no ``\0``.
  try:
    result = devRandomSalt()
  except IOError:
    result = randomSalt()

  var newResult = ""
  for i in 0 ..< result.len:
    if result[i] != '\0':
      newResult.add result[i]
  return newResult

proc makeSessionKey*(): string =
  ## Creates a random key to be used to authorize a session.
  let random = makeSalt()
  return bcrypt.hash(random, genSalt(8))

proc makePassword*(password, salt: string, comparingTo = ""): string =
  ## Creates an MD5 hash by combining password and salt.
  let bcryptSalt = if comparingTo != "": comparingTo else: genSalt(8)
  result = hash(getMD5(salt & getMD5(password)), bcryptSalt)

proc makeIdentHash*(user, password: string, epoch: int64,
                    secret: string): string =
  ## Creates a hash verifying the identity of a user. Used for password reset
  ## links and email activation links.
  ## The ``epoch`` determines the creation time of this hash, it will be checked
  ## during verification to ensure the hash hasn't expired.
  ## The ``secret`` is the 'salt' field in the ``person`` table.
  result = hmac_sha256(secret, user & password & $epoch).toHex()


when isMainModule:
  block:
    let ident = makeIdentHash("test", "pass", 1526908753, "randomtext")
    let ident2 = makeIdentHash("test", "pass", 1526908753, "randomtext")
    doAssert ident == ident2

    let invalid = makeIdentHash("test", "pass", 1526908754, "randomtext")
    doAssert ident != invalid

  block:
    let ident = makeIdentHash(
      "test",
      "$2a$08$bY85AhoD1e9u0IsD9sM7Ee6kFSLeXRLxJ6rMgfb1wDnU9liaymoTG",
      1526908753,
      "*B2a] IL\"~sh)q-GBd/i$^>.TL]PR~>1IX>Fp-:M3pCm^cFD\\um"
    )
    let ident2 = makeIdentHash(
      "test",
      "$2a$08$bY85AhoD1e9u0IsD9sM7Ee6kFSLeXRLxJ6rMgfb1wDnU9liaymoTG",
      1526908753,
      "*B2a] IL\"~sh)q-GBd/i$^>.TL]PR~>1IX>Fp-:M3pCm^cFD\\um"
    )
    doAssert ident == ident2

    let invalid = makeIdentHash(
      "test",
      "$2a$08$bY85AhoD1e9u0IsD9sM7Ee6kFSLeXRLxJ6rMgfb1wDnU9liaymoTG",
      1526908754,
      "*B2a] IL\"~sh)q-GBd/i$^>.TL]PR~>1IX>Fp-:M3pCm^cFD\\um"
    )
    doAssert ident != invalid
