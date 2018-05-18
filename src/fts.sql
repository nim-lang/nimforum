-- selects just threads,
-- those where title doesn't coinside with some of its posts' titles
-- by now selects only the threads title (no post snippet)
SELECT
        thread_id,
        snippet(thread_fts, '<b>', '</b>', '<b>...</b>') AS thread,
        0 AS post_id,
        '' AS header,
        '' AS content,
        person.name AS author,
        cdate,
        author_id,
        person.email AS email,
        0 AS what
    FROM (
        SELECT
                thread_fts.id AS thread_id,
                post.id AS post_id,
                post.creation AS cdate,
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
            LIMIT ? OFFSET (? - 1) * ?
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
            THEN snippet(post_fts, '<b>', '</b>', '...', what)
            ELSE post_fts.header END AS header,
        CASE what WHEN 2
            THEN snippet(post_fts, '**', '**', '...', what, -45)
            ELSE SUBSTR(post_fts.content, 1, 200) END AS content,
        person.name AS author,
        cdate,
        post.author AS author_id,
        person.email AS email,
        what
    FROM post_fts JOIN (
    -- inner query, selects ids of matching posts, orders and limits them,
    -- so snippets only for limited count of posts are created (in outer query)
        SELECT id, post.creation AS cdate, thread, 1 AS what, post.author AS author
            FROM post_fts JOIN post USING(id)
            WHERE post_fts.header MATCH ?
            GROUP BY post.header
            HAVING SUBSTR(post.header,1,3)<>'Re:'
        UNION
        SELECT id, post.creation AS cdate, thread, 2 AS what, post.author AS author
            FROM post_fts JOIN post USING(id)
            WHERE post_fts.content MATCH ?
        ORDER BY what, cdate DESC
        LIMIT ? OFFSET (? - 1) * ?
    ) AS post USING(id)
        JOIN thread ON thread.id=thread
        JOIN person ON person.id=author
    WHERE post_fts MATCH ?
ORDER BY what ASC, cdate DESC
LIMIT 300 -- hardcoded limit just in case
;

