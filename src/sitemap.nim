import simpleSitemap, db_sqlite, times, os, uri

type
  SitemapGenerator* = object
    dbconn: Dbconn
    hostname: Uri

proc newSitemapGenerator*(dbconn: DbConn, hostname: string): SitemapGenerator =
  ## The generator for sitemaps `dbconn` is the forums database, `hostname` is the absolute url
  ## the forum runs on.
  result = SitemapGenerator()
  result.dbconn = dbconn
  result.hostname = parseUri(hostname)

proc generate*(sg: SitemapGenerator) =
  ## Generates the xml sitemap(s) creates them in `getAppDir() / "public"`
  var urlDates: seq[UrlDate] = @[]
  for row in sg.dbconn.rows(sql"select id, modified from thread"):
    let absurl = sg.hostname / "t" / row[0]
    let pdate = row[1].parse("yyyy-MM-dd H':'m':'s")
    urlDates.add ($absurl, pdate)
  let pages = generateSitemaps(
    urlDates,
    urlsOnRecent = 30,
    maxUrlsPerSitemap = 50_000,
    base = $sg.hostname
  )
  write(pages, folder = getAppDir() / "public")