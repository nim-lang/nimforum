#
#
#              The Nim Forum
#        (c) Copyright 2018 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#
# Script to initialise the nimforum.

import strutils, db_sqlite, os, times, json, options, terminal

import auth, frontend/user

proc backup(path: string, contents: Option[string]=none[string]()) =
  if existsFile(path):
    if contents.isSome() and readFile(path) == contents.get():
      # Don't backup if the files are equivalent.
      echo("Not backing up because new file is the same.")
      return

    let backupPath = path & "." & $getTime().toUnix()
    echo(path, " already exists. Moving to ", backupPath)
    moveFile(path, backupPath)

proc createUser(db: DbConn, user: tuple[username, password, email: string],
                rank: Rank) =
  assert user.username.len != 0
  let salt = makeSalt()
  let password = makePassword(user.password, salt)

  exec(db, sql"""
    INSERT INTO person(name, password, email, salt, status, lastOnline)
    VALUES (?, ?, ?, ?, ?, DATETIME('now'))
  """, user.username, password, user.email, salt, $rank)

proc initialiseDb(admin: tuple[username, password, email: string],
                  filename="nimforum.db") =
  let
    path = getCurrentDir() / filename
    isTest = "-test" in filename
    isDev = "-dev" in filename

  if not isDev and not isTest:
    backup(path)

  removeFile(path)

  var db = open(connection=path, user="", password="",
                database="nimforum")

  const
    userNameType = "varchar(20)"
    passwordType = "varchar(300)"
    emailType = "varchar(254)" # https://stackoverflow.com/a/574698/492186

  # -- Category

  db.exec(sql"""
    create table category(
      id integer primary key,
      name varchar(100) not null,
      description varchar(500) not null,
      color varchar(10) not null
    );
  """)

  db.exec(sql"""
    insert into category (id, name, description, color)
    values (0, 'Default', '', '');
  """)

  # -- Thread

  db.exec(sql"""
  create table thread(
    id integer primary key,
    name varchar(100) not null,
    views integer not null,
    modified timestamp not null default (DATETIME('now')),
    category integer not null default 0,
    isLocked boolean not null default 0,
    solution integer,
    isDeleted boolean not null default 0,

    foreign key (category) references category(id),
    foreign key (solution) references post(id)
  );""", [])

  db.exec(sql"""
    create unique index ThreadNameIx on thread (name);
  """, [])

  # -- Person

  db.exec(sql("""
  create table person(
    id integer primary key,
    name $# not null,
    password $# not null,
    email $# not null,
    creation timestamp not null default (DATETIME('now')),
    salt varbin(128) not null,
    status varchar(30) not null,
    lastOnline timestamp not null default (DATETIME('now')),
    previousVisitAt timestamp not null default (DATETIME('now')),
    isDeleted boolean not null default 0,
    needsPasswordReset boolean not null default 0
  );""" % [userNameType, passwordType, emailType]), [])

  db.exec(sql"""
    create unique index UserNameIx on person (name);
  """, [])
  db.exec sql"create index PersonStatusIdx on person(status);"

  # Create default user.
  db.createUser(admin, Admin)

  # Create test users if test or development
  if isTest or isDev:
    for rank in Spammer..Moderator:
      let rankLower = toLowerAscii($rank)
      let user = (username: $rankLower,
                  password: $rankLower,
                  email: $rankLower & "@localhost.local")
      db.createUser(user, rank)

  # -- Post

  db.exec(sql"""
    create table post(
      id integer primary key,
      author integer not null,
      ip inet not null,
      content varchar(1000) not null,
      thread integer not null,
      creation timestamp not null default (DATETIME('now')),
      isDeleted boolean not null default 0,
      replyingTo integer,

      foreign key (thread) references thread(id),
      foreign key (author) references person(id),
      foreign key (replyingTo) references post(id)
    );""", [])

  db.exec sql"create index PostByAuthorIdx on post(thread, author);"

  db.exec(sql"""
    create table postRevision(
      id integer primary key,
      creation timestamp not null default (DATETIME('now')),
      original integer not null,
      content varchar(1000) not null,

      foreign key (original) references post(id)
    )
  """)

  # -- Session

  db.exec(sql("""
    create table session(
      id integer primary key,
      ip inet not null,
      key $# not null,
      userid integer not null,
      lastModified timestamp not null default (DATETIME('now')),
      foreign key (userid) references person(id)
    );""" % [passwordType]), [])

  # -- Likes

  db.exec(sql("""
    create table like(
      id integer primary key,
      author integer not null,
      post integer not null,
      creation timestamp not null default (DATETIME('now')),

      foreign key (author) references person(id),
      foreign key (post) references post(id)
    )
  """))

  # -- Report

  db.exec(sql("""
    create table report(
      id integer primary key,
      author integer not null,
      post integer not null,
      kind varchar(30) not null,
      content varchar(500) not null default '',

      foreign key (author) references person(id),
      foreign key (post) references post(id)
    )
  """))

  # -- FTS

  if not db.tryExec(sql"""
      CREATE VIRTUAL TABLE thread_fts USING fts4 (
        id INTEGER PRIMARY KEY,
        name VARCHAR(100) NOT NULL
      );""", []):
    echo "thread_fts table already exists or fts4 not supported"
  else:
    db.exec(sql"""
      INSERT INTO thread_fts
      SELECT id, name FROM thread;
    """, [])
  if not db.tryExec(sql"""
      CREATE VIRTUAL TABLE post_fts USING fts4 (
        id INTEGER PRIMARY KEY,
        content VARCHAR(1000) NOT NULL
      );""", []):
    echo "post_fts table already exists or fts4 not supported"
  else:
    db.exec(sql"""
      INSERT INTO post_fts
      SELECT id, content FROM post;
    """, [])

  close(db)

proc initialiseConfig(
  name, title, hostname: string,
  recaptcha: tuple[siteKey, secretKey: string],
  smtp: tuple[address, user, password: string],
  isDev: bool,
  dbPath: string,
  ga: string=""
) =
  let path = getCurrentDir() / "forum.json"

  var j = %{
    "name": %name,
    "title": %title,
    "hostname": %hostname,
    "recaptchaSiteKey": %recaptcha.siteKey,
    "recaptchaSecretKey": %recaptcha.secretKey,
    "smtpAddress": %smtp.address,
    "smtpUser": %smtp.user,
    "smtpPassword": %smtp.password,
    "isDev": %isDev,
    "dbPath": %dbPath
  }
  if ga.len > 0:
    j["ga"] = %ga

  backup(path, some(pretty(j)))
  writeFile(path, pretty(j))

proc question(q: string): string =
  while result.len == 0:
    stdout.write(q)
    result = stdin.readLine()

proc setup() =
  echo("""
Welcome to the NimForum setup script. Please answer the following questions.
These can be changed later in the generated forum.json file.
  """)

  let name = question("Forum full name: ")
  let title = question("Forum short name: ")

  let hostname = question("Forum hostname: ")

  let adminUser = question("Admin username: ")
  let adminPass = readPasswordFromStdin("Admin password: ")
  let adminEmail = question("Admin email: ")

  echo("")
  echo("The following question are related to recaptcha. \nYou must set up a " &
       "recaptcha for your forum before answering them. \nPlease do so now " &
       "and then answer these questions: https://www.google.com/recaptcha/admin")
  let recaptchaSiteKey = question("Recaptcha site key: ")
  let recaptchaSecretKey = question("Recaptcha secret key: ")


  echo("The following questions are related to smtp. You must set up a \n" &
       "mailing server for your forum or use an external service.")
  let smtpAddress = question("SMTP address (eg: mail.hostname.com): ")
  let smtpUser = question("SMTP user: ")
  let smtpPassword = readPasswordFromStdin("SMTP pass: ")

  echo("The following is optional. You can specify your Google Analytics ID " &
       "if you wish. Otherwise just leave it blank.")
  stdout.write("Google Analytics (eg: UA-12345678-1): ")
  let ga = stdin.readLine().strip()

  let dbPath = "nimforum.db"
  initialiseConfig(
    name, title, hostname, (recaptchaSiteKey, recaptchaSecretKey),
    (smtpAddress, smtpUser, smtpPassword), isDev=false,
    dbPath, ga
  )

  initialiseDb(
    admin=(adminUser, adminPass, adminEmail),
    dbPath
  )

  echo("Setup complete!")

proc echoHelp() =
    quit("""
Usage: setup_nimforum opts

Options:
  --setup         Performs first time setup for end users.

Development options:
  --dev           Creates a new development DB and config.
  --test          Creates a new test DB and config.
  --blank         Creates a new blank DB.
  """)

when isMainModule:
  if paramCount() > 0:
    case paramStr(1)
    of "--dev":
      let dbPath = "nimforum-dev.db"
      echo("Initialising nimforum for development...")
      initialiseConfig(
        "Development Forum",
        "Development Forum",
        "localhost",
        recaptcha=("", ""),
        smtp=("", "", ""),
        isDev=true,
        dbPath
      )

      initialiseDb(
        admin=("admin", "admin", "admin@localhost.local"),
        dbPath
      )
    of "--test":
      let dbPath = "nimforum-test.db"
      echo("Initialising nimforum for testing...")
      initialiseConfig(
        "Test Forum",
        "Test Forum",
        "localhost",
        recaptcha=("", ""),
        smtp=("", "", ""),
        isDev=true,
        dbPath
      )

      initialiseDb(
        admin=("admin", "admin", "admin@localhost.local"),
        dbPath
      )
    of "--blank":
      let dbPath = "nimforum-blank.db"
      echo("Initialising blank DB...")
      initialiseDb(
        admin=("", "", ""),
        dbPath
      )
    of "--setup":
      setup()
    else:
      echoHelp()
  else:
    echoHelp()


