#
#
#              The Nim Forum
#        (c) Copyright 2018 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#
# Script to initialise the nimforum.

import strutils, db_sqlite, os, times, json, options

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

proc initialiseDb(admin: tuple[username, password, email: string],
                  filename="nimforum.db") =
  let path = getCurrentDir() / filename
  if "-dev" notin filename and "-test" notin filename:
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
    isDeleted boolean not null default 0,
    needsPasswordReset boolean not null default 0
  );""" % [userNameType, passwordType, emailType]), [])

  db.exec(sql"""
    create unique index UserNameIx on person (name);
  """, [])
  db.exec sql"create index PersonStatusIdx on person(status);"

  # Create default user.
  let salt = makeSalt()
  let password = makePassword(admin.password, salt)
  db.exec(sql"""
    insert into person (id, name, password, email, salt, status)
    values (0, ?, ?, ?, ?, ?);
  """, admin.username, password, admin.email, salt, $Admin)

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
  dbPath: string
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

  backup(path, some(pretty(j)))
  writeFile(path, pretty(j))

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
    else:
      quit("--dev|--test")
