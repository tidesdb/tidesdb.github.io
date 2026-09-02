---
title: Quickstart
description: Open a database, write a key, read it back — the TidesDB Python binding in five minutes.
---

# Quickstart

A minimal end-to-end example. `title` and `description` above are the only
required frontmatter — the website injects the versioned `slug` from
`manual.json` at sync time, so you never maintain the URL by hand.

```python
import tidesdb

db = tidesdb.open("./data")
cf = db.column_family("default")

cf.put(b"hello", b"world")
print(cf.get(b"hello"))  # b"world"

db.close()
```

Write normal Markdown from here — headings, code blocks, tables, and Starlight
asides (`:::note`) all work exactly as they do in the core manual.
