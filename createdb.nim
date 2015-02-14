#
#
#              The Nimrod Forum
#        (c) Copyright 2012 Andreas Rumpf, Dominik Picheta
#        Look at license.txt for more info.
#        All rights reserved.
#

import strutils, db_sqlite

var db = open(connection="nimforum.db", user="postgres", password="", 
              database="nimforum")

const 
  TUserName = "varchar(20)"
  TPassword = "varchar(32)"
  TEmail = "varchar(30)"

db.exec(sql"""
create table if not exists thread(
  id integer primary key,
  name varchar(100) not null,
  views integer not null,
  modified timestamp not null default (DATETIME('now'))
);""", [])

db.exec(sql"""
create unique index if not exists ThreadNameIx on thread (name);
""", [])

db.exec(sql("""
create table if not exists person(
  id integer primary key,
  name $# not null,
  password $# not null,
  email $# not null,
  creation timestamp not null default (DATETIME('now')),
  salt varbin(128) not null,
  status integer not null,
  admin bool default false,
  lastOnline timestamp not null default (DATETIME('now'))
);""" % [TUserName, TPassword, TEmail]), [])
#  echo "person table already exists"

db.exec(sql("""
alter table person
add ban varchar(128) not null default ''
"""))

db.exec(sql"""
create unique index if not exists UserNameIx on person (name);
""", [])

# ----------------------- Forum ------------------------------------------------


if not db.tryExec(sql"""
create table if not exists post(
  id integer primary key,
  author integer not null,
  ip inet not null,
  header varchar(100) not null,
  content varchar(1000) not null,
  thread integer not null,
  creation timestamp not null default (DATETIME('now')),
  
  foreign key (thread) references thread(id),
  foreign key (author) references person(id)
);""", []):
  echo "post table already exists"

# -------------------- Session -------------------------------------------------

if not db.tryExec(sql("""
create table if not exists session(
  id integer primary key,
  ip inet not null,
  password $# not null,
  userid integer not null,
  lastModified timestamp not null default (DATETIME('now')),
  foreign key (userid) references person(id)
);""" % [TPassword]), []):
  echo "session table already exists"

if not db.tryExec(sql"""
create table if not exists antibot(
  id integer primary key,
  ip inet not null,
  answer varchar(30) not null,
  created timestamp not null default (DATETIME('now'))
);""", []):
  echo "antibot table already exists"

# -------------------- Search --------------------------------------------------

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
      header VARCHAR(100) NOT NULL,
      content VARCHAR(1000) NOT NULL
    );""", []):
  echo "post_fts table already exists or fts4 not supported"
else:
  db.exec(sql"""
    INSERT INTO post_fts
    SELECT id, header, content FROM post;
  """, [])


# ------------------------------------------------------------------------------

#discard stdin.readline()

close(db)
