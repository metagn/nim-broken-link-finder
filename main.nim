include prelude
import algorithm, deques, httpclient, re, sequtils, strformat, uri

# Where crawling will start from.
const crawlStart {.strdefine.} = "https://nim-lang.github.io/Nim/"

# Any visited URL that starts with `crawlBase` will also be checked for broken links.
const crawlBase {.strdefine.} = "https://nim-lang.github.io/Nim/"

# URLs starting with any of these strings will be ignored.
const ignoredUrls = [
  "https://github.com/nim-lang/Nim/tree/", # "Source" links.
  "https://github.com/nim-lang/Nim/edit/", # "Edit" links.
]

const outputPath = "broken_links.txt"

const timeoutMillisecs = 10_000
const maxRetries = 10

let tagPattern = re"""<([^>"]*"[^"]*")*>"""
let idPattern = re""" id="([^"]+)""""
let namePattern = re""" name="([^"]+)""""
let hrefPattern = re""" href="([^"]+)""""
let lineNumberPattern = re"^L\d+$"

type
  Task = tuple[source: string, dest: string, fragment: string]
  Tasks = Deque[Task]
  BrokenLinks = Table[string, CountTable[string]]

proc idsAndHrefs(html: string): (HashSet[string], seq[string]) =
  var a, b: int
  for tag in html.findall(tagPattern):
    (a, b) = tag.findBounds(idPattern)
    if a != -1:
      result[0].incl(tag[a + 5 .. b - 1])

    if tag.startsWith("<a "):
      # Also include the name attribute on "a" elements in the IDs.
      (a, b) = tag.findBounds(namePattern)
      if a != -1:
        result[0].incl(tag[a + 7 .. b - 1])

      (a, b) = tag.findBounds(hrefPattern)
      if a != -1:
        result[1].add(tag[a + 7 .. b - 1])

proc decodeUrlAndHtmlEntities(url: string): string =
  result = decodeUrl(url).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")

proc addTasks(tasks: var Tasks, addedUrls: var HashSet[string], curUrl: string, hrefs: seq[string]) =
  for href in hrefs:
    if ignoredUrls.anyIt(href.startsWith(it)):
        continue

    let
      linkUrl = $combine(parseUri(curUrl), parseUri(href))
      fragmentSplit = linkUrl.split('#', 1)
      dest = fragmentSplit[0]
      fragment = if fragmentSplit.len == 2: fragmentSplit[1] else: ""

    if dest notin addedUrls:
      tasks.addLast((source: "", dest: dest, fragment: ""))
      addedUrls.incl(dest)

    tasks.addLast((source: curUrl, dest: dest, fragment: fragment))

proc logBrokenLinks(f: File, source: string, brokenLinks: BrokenLinks) =
  if source in brokenLinks:
    let links = brokenLinks[source]
    f.writeLine(source)
    var
      fragmentLinks: seq[string]
      localLinks: seq[string]
      remoteLinks: seq[string]

    for link, count in links:
      var linkStr = if count > 1: fmt"({count}) {link}" else: fmt"    {link}"

      if link.startsWith(source):
        fragmentLinks.add(linkStr)
      elif link.startsWith(crawlBase):
        localLinks.add(linkStr)
      else:
        remoteLinks.add(linkStr)

    fragmentLinks.sort()
    localLinks.sort()
    remoteLinks.sort()

    for link in fragmentLinks & localLinks & remoteLinks:
      f.writeLine(link)

    f.writeLine("")

proc main() =
  let outputFile = open(outputPath, fmWrite)
  defer: outputFile.close()

  var
    tasks: Tasks
    addedUrls: HashSet[string]
    cachedIds: Table[string, HashSet[string]]
    failedUrls: HashSet[string]
    brokenLinks: BrokenLinks

  tasks.addLast((source: "", dest: crawlStart, fragment: ""))
  addedUrls.incl(crawlStart)
  var prevSource = crawlStart

  while tasks.len > 0:
    let task = tasks.popFirst

    if task.source.len == 0:
      # Crawl new URL.
      echo "Tasks remaining: ", tasks.len, " - Requesting: ", task.dest

      block doRequest:
        var
          res: Response
          retry = 0

        while true:
          try:
            res = newHttpClient(timeout = timeoutMillisecs).request(task.dest)
            break
          except:
            echo getCurrentExceptionMsg()
            inc retry
            if retry > maxRetries:
              echo "Max retries reached"
              failedUrls.incl(task.dest)
              break doRequest

        if res.status == "200 OK":
          let html = res.body
          let (ids, hrefs) = idsAndHrefs(html)
          cachedIds[task.dest] = ids
          if task.dest.startsWith(crawlBase):
            tasks.addTasks(addedUrls, task.dest, hrefs)

        else:
          failedUrls.incl(task.dest)

    else:
      if task.source != prevSource:
        outputFile.logBrokenLinks(prevSource, brokenLinks)
        prevSource = task.source

      # Check if the link is broken.
      if (
        task.dest in failedUrls or
        (
          task.fragment.len != 0 and
          task.fragment notin cachedIds[task.dest] and
          task.fragment.decodeUrlAndHtmlEntities notin cachedIds[task.dest] and
          not task.fragment.match(lineNumberPattern)
        )
      ):
        var destWithFragment = task.dest
        if task.fragment.len != 0:
          destWithFragment.add('#')
          destWithFragment.add(task.fragment)

        brokenLinks.mgetOrPut(task.source, initCountTable[string]()).inc(destWithFragment)

  outputFile.logBrokenLinks(prevSource, brokenLinks)

main()

proc checkCI() =
  let content = readFile(outputPath)
  if content.len != 0:
    echo "Broken links:"
    echo content
    quit(1)

checkCI()
