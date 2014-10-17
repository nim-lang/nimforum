import tables, uri
type
  CacheInfo = object
    valid: bool
    value: string

  CacheHolder = ref object
    caches: Table[string, CacheInfo]

proc normalizePath(x: string): string =
  let u = parseUri(x)
  result = u.path & (if u.query != "": '?' & u.query else: "")

proc newCacheHolder*(): CacheHolder =
  new result
  result.caches = initTable[string, CacheInfo]()

proc invalidate*(cache: CacheHolder, name: string) =
  cache.caches.mget(name.normalizePath()).valid = false

proc invalidateAll*(cache: CacheHolder) =
  for key, val in mpairs(cache.caches):
    val.valid = false

template get*(cache: CacheHolder, name: string, grabValue: expr): expr =
  ## Check to see if the cache contains value for ``name``. If it does and the
  ## cache is valid then doesn't recalculate it but returns the cached version.
  echo(cache.caches)
  mixin normalizePath
  let nName = name.normalizePath()
  if not (cache.caches.hasKey(nName) and cache.caches[nName].valid):
    echo "Resetting cache."
    cache.caches[nName] = CacheInfo(valid: true, value: grabValue)
  cache.caches[nName].value
