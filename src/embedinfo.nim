# This program inserts whatever command line parameters it receives
# in a <meta> generator tag in karax.html
# Each parameter is separated by a dash in the <meta> tag.

# So, `embedinfo Version GitCommit`
# Will result in `<meta name="generator" content="Nimforum Version - GitCommit">`
# being added to public/karax.html right after the </title> tag
import std/[os, strutils]

if paramCount() == 0:
  quit("Usage: embedinfo [Version] (Commit)")

# Open public/karax.html and loop over every line
# If the line has an ending <title> tag then we insert
# our HTML after it.
var output = ""
for line in readFile("public/karax.html").splitLines:
  output.add(line & "\n")

  if "</title>" in line:
    output.add("  <meta name=\"generator\" content=\"Nimforum ")
    for param in commandLineParams():
      output.add(param & " - ")
    output = output[0..^4] # Remove last dash
    output.add("\">")

# Write everything into a new file.
writeFile("public/karax.ver.html", output)