---
title: What is TidesDB?
description: A high level description of what TidesDB is.
---

TidesDB is a C library which provides fast storage.  The TidesDB library can be accessed through a variety of FFI libraries.

TidesDB can be considered an embedded and persistent key-value store with an underlaying log-structured-merge tree data structure.

Keys and values in TidesDB are simply raw sequences of bytes with no predetermined size restrictions.