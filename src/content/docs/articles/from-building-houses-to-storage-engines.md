---
title: "From Building Houses to Storage Engines"
description: "The journey of how TidesDB came to be."
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/angel-alex-beach.png
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/angel-alex-beach.png
---


*by Alex Gaetano Padula*

*published on January 16th, 2026*

I get asked pretty regularly about my process for getting to the point of coming up with and building TidesDB.

<div class="article-image small-article-image">

![The Process of Building TidesDB](/angel-alex-beach.png)

</div>

It all starts when I was a child. I got my first computer, I was obsessed. I would take it apart, rebuild it, and try to understand how it worked. I did this with most electronics I had as a kid. This naturally led me to the world of programming. My first language was Visual Basic and I was rather young at the time, I think I was 12 or 13 years old. After that I got into C, C++, and all kinds of languages and frameworks through the years. I'm just a naturally curious person and I love getting deep into things and understanding how they work. Programming has always been an escape for me, hours fly by and I don't even notice.  It's a passion and absolute joy.  In the toughest times, I would always find solace in programming.  

Unfortunately for me I had a tough time growing up and it wasn't easy to go to school due to internal family issues. I had to start working very young, my first job I would do coat check with my father, I remember then working with my uncle in construction, I grew a very strong work ethic and drive to succeed during those times.  


<img width="128" style="float: left; margin-right: 10px;" src="/alex-carpenter.jpeg" alt="Alex Gaetano Padula Carpenter" />

I've worked many careers in my life and even during all those times I always programmed, whether it was a web app I thought was cool like GIFSOM which was an early GIF social network, or a website or application for a client working freelance.  I've worked many jobs, I've been a carpenter, I've been a train conductor, I've cooked food at restaurants.  I've done a lot, and I've learned and continue to learn.  Life is all about experiences, learning, growing, and sometimes jumping into hard situations for me.

A few years ago I started to tinker with storage systems. I wrote _so many_ naive and rather good implementations from basic n-ary disk storage, to btrees, to even a <a href="https://github.com/fairymq" target="_blank">distributed message queue</a>. I even wrote <a href="https://github.com/cursusdb/cursusdb" target="_blank">CursusDB</a>, which is a distributed in-memory document database with real time capabilities. This was one of my first storage systems I ever wrote, and it wasn't that great but I learned so much just from building from first principles. I got curious about how could I store data on disk? How could I allow for better concurrency? Parallelism? Protocols? Replication? Sharding? So many questions sprung up. 


I remember an email from Andy Pavlo, who I did not know at the time, regarding CursusDB. This was very cool. I was exposed to <a href="https://www.youtube.com/c/CMUDatabaseGroup">Carnegie Mellon Database Group</a> which has many amazing lectures online. I've probably gone through all the videos three times, just playing them, absorbing them, even listening to them. I just really had an interest in what was being taught. I already wrote a couple storage systems but this did expose me to so much more. I was exposed to so many different ideas and concepts that I never even knew existed. I was blown away, I was so excited, I got my hands on papers, specifications, books. I like to implement. I get a general idea of, say, how a data structure works and then attempt to write it based on my understanding.  


From there I wrote an SQL storage system called AriaSQL - it is like an SQL server based on <a href="https://nvlpubs.nist.gov/nistpubs/Legacy/FIPS/fipspub127.pdf" target="_blank">SQL-86 specification (ANSI X3.135-1986)</a>. This also taught me a lot about how SQL works as a language, about how to parse, lexical analysis, syntax analysis, semantic analysis, optimization, and execution. From there I naturally got curious about storage engines. What kinds are out there? How are they implemented? What are they missing? What are the best storage engines? I then stumbled onto the <a href="https://en.wikipedia.org/wiki/Log-structured_merge-tree" target="_blank">LSM tree</a>. 

<img width="128" style="float: left; margin: 10px;" src="/alex-favorite-mug.jpeg" alt="Alex's favorite mug" />
The LSM tree just clicked in my head. I had so many ideas on what an LSM could look like. I started to write many different LSM tree projects from <a href="https://github.com/guycipher/lsmt" target="_blank">LSMT</a>, to <a href="https://github.com/guycipher/k4" target="_blank">K4</a>, <a href="https://github.com/starskey-io/starskey" target="_blank">Starskey</a>, to <a href="https://github.com/wildcatdb/wildcatdb" target="_blank">WildcatDB</a>. Each project taught me something different and led me closer to building the storage engine that would be TidesDB 7. In early versions of TidesDB we had a single writer, we had pair-wise merging, it was different but again each previous project TidesDB still existed but I was writing other projects to learn and experiment with different ideas. For example in Starskey we had hierarchical disk levels similar to say LevelDB, compact index structures, key-value separation (<a href="https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf">WiscKey</a>). From there, I wanted to learn more about writing a system that was lock-free and concurrent so I wrote WildcatDB which is a highly concurrent Go key-value storage system. It utilizes timestamps for its MVCC implementation, lock-free atomics, it's rather cool. 


After writing WildcatDB I noticed that lock-free had some spectacular advantages.  I then started to think how I could design TidesDB to utilize this lock-free and hierarchical architecture. This did not start right away, TidesDB grew from an alpha to a beta through to many majors.  The past few months I really pushed through a lot of majors refining the compact disk format, compaction algorithm, lock-free architecture, and more.  This only became possible when I unfortunately lost my job. What could have been devastating became an opportunity, I channeled everything into TidesDB, sometimes 16 hours a day, sometimes into the next day. I couldn't stop, I wanted to get TidesDB where I thought it should be.

<img width="128" style="float: left; margin: 10px;" src="/alex-niv.jpeg" alt="Alex University Toronto Trip'" />I have to mention <a href="https://www.nivdayan.net/">Niv Dayan</a>, who invited me to meet his lab for a roundtable discussion. This greatly inspired me to think how I could incorporate their work into this design I had in my head.  His lab has pushed some amazing work in the LSM tree space such as <a href="https://vldb.org/pvldb/vol15/p3071-dayan.pdf">Spooky</a>/ <a href="https://www.youtube.com/watch?v=0CVh6B8oAnE&t=1s">Video on Spooky</a>.  I thank him for the inspiration, very much so in designing a storage engine that could be adaptive to the data that is being stored among other things. 

My main goal was to design a storage engine that could scale with the cores you have on your system and a decent amount of memory. Utilizing the latest storage research, offering the easiest and most effective API for database development and offering the best performance possible on modern hardware.  It's interesting to see today where TidesDB is. Benchmarking it against RocksDB v10.9.1, the extensive benchtool suite shows TidesDB surpassing the industry standard in pretty much every aspect which is incredibly hard to believe for me even, but the truth is that's **true**, and I cannot wait to keep benchmarking TidesDB on different systems as the opportunities present themselves. The entire time, I've been open, honest, showed where we fail and continued to optimize. You can see the latest benchmarks <a href="https://tidesdb.com/articles/benchmark-analysis-tidesdb-v7-2-3-rocksdb-v10-9-1/">here</a>.  

To end, it wasn't easy. It took a lot of time and effort. I worked before work, after work, weekends, holidays. I never gave up, I stayed consistent, and I only want TidesDB to keep getting better. I continue to improve and optimize, I can't help myself but everyday reviewing, finding something to improve. I hope you take the time to try TidesDB out, join the <a href="https://discord.gg/tWEmjR66cy">Discord</a>, let me know your thoughts, I'm always open to answering questions and I'm always open to learning with you all.  We have a growing community as well of awesome people who are open to learning and contributing to TidesDB and that's fantastic, I'm grateful for you all.

*Thanks for reading!*

---

**Links**
- GitHub · https://github.com/tidesdb/tidesdb
- Design deep-dive · https://tidesdb.com/getting-started/how-does-tidesdb-work
- TidesDB Database Internals Presentation · https://www.youtube.com/watch?v=7HROlAaiGVQ

Thank you to <a href="https://github.com/balagrivine">Bala Grivine</a> for the feedback on the article!