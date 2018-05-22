-- selects just threads,
-- those where title doesn't coinside with some of its posts' titles
-- by now selects only the threads title (no post snippet)
SELECT
        thread_id,
        snippet(thread_fts, '<b>', '</b>', '<b>...</b>') AS thread,
        post_id,
        post_content,
        cdate,
        person.name AS author,
        person.email AS email,
        strftime('%s', person.lastOnline) AS lastOnline,
        strftime('%s', person.previousVisitAt) AS previousVisitAt,
        person.status AS status,
        person.isDeleted as person_isDeleted,
        0 AS what
    FROM (
        SELECT
                thread_fts.id AS thread_id,
                post.id AS post_id,
                post.content AS post_content,
                strftime('%s', post.creation) AS cdate,
                MIN(post.creation) AS cdate,
                post.author AS author_id
            FROM thread_fts
            JOIN post ON post.thread=thread_id
            WHERE thread_fts MATCH ?
            GROUP BY thread_id, post_id
            HAVING thread_id NOT IN (
                SELECT thread
                    FROM post_fts JOIN post USING(id)
                    WHERE post_fts MATCH ?
            )
            LIMIT ? OFFSET ?
    )
        JOIN thread_fts ON thread_fts.id=thread_id
        JOIN person ON person.id=author_id
    WHERE thread_fts MATCH ?
UNION
-- the main query, selects posts
SELECT
        thread.id AS thread_id,
        thread.name AS thread,
        post.id AS post_id,
        CASE what WHEN 1
            THEN snippet(post_fts, '**', '**', '...', what, -45)
            ELSE SUBSTR(post_fts.content, 1, 200) END AS content,
        cdate,
        person.name AS author,
        person.email AS email,
        strftime('%s', person.lastOnline) AS lastOnline,
        strftime('%s', person.previousVisitAt) AS previousVisitAt,
        person.status AS status,
        person.isDeleted as person_isDeleted,
        what
    FROM post_fts JOIN (
    -- inner query, selects ids of matching posts, orders and limits them,
    -- so snippets only for limited count of posts are created (in outer query)
        SELECT id, strftime('%s', post.creation) AS cdate, thread, 1 AS what, post.author AS author
            FROM post_fts JOIN post USING(id)
            WHERE post_fts.content MATCH ?
        ORDER BY what, cdate DESC
        LIMIT ? OFFSET ?
    ) AS post USING(id)
        JOIN thread ON thread.id=thread
        JOIN person ON person.id=author
    WHERE post_fts MATCH ?
ORDER BY what ASC, cdate DESC
LIMIT 300 -- hardcoded limit just in case
;

