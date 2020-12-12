# Nim Broken Link Finder
A tool for finding broken links on your website.

To compile and run the script:
```
nim r -d:ssl main.nim
```
(The `-d:ssl` is needed to load URLs that start with `https`. See
[here](https://nim-lang.org/docs/httpclient.html#sslslashtls-support)
for details.)

In `main.nim`, set `crawlStart` and `crawlBase` to configure which pages 
will be crawled.
Crawling starts at the `crawlStart` URL, and if any links are found on 
that page that point to URLs that start with `crawlBase`, those URLs 
will be recursively crawled.

For example, to crawl the latest Nim docs, set them to:
```
const crawlStart = "https://nim-lang.github.io/Nim/"
const crawlBase = "https://nim-lang.github.io/Nim/"
```

You can ignore certain URLs with `ignoredUrls`.
Any links pointing to URLs that start with any of these strings will be 
ignored. For example:
```
const ignoredUrls = [
  "https://github.com/nim-lang/Nim/tree/devel/",
  "https://github.com/nim-lang/Nim/edit/devel/",
]
```

The output file will be written to `outputPath` (overwriting any existing file at that path). For example:
```
const outputPath = "broken_links.txt"
```

Each link found on a crawled page is checked by:
* Requesting the URL that the link points to and making sure it
  returns with a status code of `200 OK`. Any other status code, 
  such as a 404 error or a redirect, is considered a broken link.
* If the link's URL contains a fragment (the part after the #),
  the requested page is checked to see if it contains an HTML element
  with an `id` attribute matching that fragment string. If one cannot be
  found, the link is considered broken. 

Below is an example output. It shows that
[tut1.html](https://nim-lang.github.io/Nim/tut1.html) has 2 broken links,
and
[random.html](https://nim-lang.github.io/Nim/random.html)
has 8 broken links (4 for each of the broken URLs). When a broken URL is 
pointed to by more than one link, the number of links pointing to that
URL will be shown in parentheses to the left of it.
```
https://nim-lang.github.io/Nim/tut1.html
    https://nim-lang.github.io/Nim/system.html#items.i,seq[T]
    https://nim-lang.github.io/Nim/system.html#pairs.i,seq[T]
    
https://nim-lang.github.io/Nim/random.html
(4) https://nim-lang.github.io/Nim/random.html#rand,HSlice[T,T]
(4) https://nim-lang.github.io/Nim/random.html#rand,Rand,HSlice[T,T]
```

## License

[MIT](LICENSE)