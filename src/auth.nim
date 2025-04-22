import md5, std/sysrand

import bcrypt, hmac

proc devRandomSalt(length = 128): string =
  result = ""
  for i in urandom(length):
    if i >= 32 and i <= 126:
      result.add(char(i))
  return result

proc makeSalt*(length = 128): string =
  ## Creates a salt using a cryptographically secure random number generator.
  ##
  ## Ensures that the resulting salt contains no ``\0``.
  result = ""
  for ch in devRandomSalt(length):
    case ch:
    of '\0': continue
    else: result.add(ch)

  return result

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
