import strutils
import karax / [karaxdsl, vdom]

const html = """
<!DOCTYPE html>
<html>
<head>
  <title>$1</title>
</head>
<body>
$2
</body>
</html>
"""

type Fortune* = ref object
  id*:int
  message*:string

proc newFortune*(id:int;message:string):Fortune =
  result = new Fortune
  result.id = id
  result.message = message

proc buildTable( data:seq[Fortune]):VNode = 
  result = buildHtml(table):
    tr:
      th(text="id")
      th(text="message")
    for row in data:
      tr:
        td:
          text $(row.id)
        td:
          text $(row.message)
  

proc fortuneView*( data:sink seq[Fortune] ):string =
  let title = "Fortunes"
  return html % [title,$buildTable(data)]

when isMainModule:
  let data = @[
    newFortune(1,"2"),
    newFortune(3,"4")
  ]
  echo fortuneView(data)
