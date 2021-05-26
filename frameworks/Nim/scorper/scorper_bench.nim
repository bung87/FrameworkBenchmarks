import std / [macros,random,json,strformat,os,cgi,strutils,algorithm,nativesockets,exitprocs]
import scorper
import amysql
import ./scorper_bench/fortune_view

proc getIP(host: string): string = 
    result = nativesockets.getHostByName(host).addrList[0]

const DB_DRIVER = getEnv("DB_DRIVER", "mysql")
# const DB_HOST = getEnv("DB_HOST", "tfb-database:3306")
let ipAddr = getIP("tfb-database")

let port = 3306
const DB_USER = getEnv("DB_USER", "benchmarkdbuser")
const DB_PASSWORD = getEnv("DB_PASSWORD", "benchmarkdbpass")
const DB_DATABASE = getEnv("DB_DATABASE", "hello_world")
let DB_DSN = fmt"mysql://{DB_USER}:{DB_PASSWORD}@{ipAddr}:{port}/{DB_DATABASE}"

var conn{.threadvar.}:Connection
try:
  conn = waitFor amysql.open(DB_DSN)
except Exception as e:
  echo e.msg

type AsyncCallback = proc (request: Request): Future[void] {.closure, gcsafe, raises: [].}

proc jsonHandler(req: Request) {.route("get","/json"),async.} = 
  let headers = {"Content-type": "application/json"}
  await req.resp("""{"message":"Hello, World!"}""",headers.newHttpHeaders())

proc plaintextHandler(req: Request) {.route("get","/plaintext"),async.} = 
  let headers = {"Content-type": "text/plain"}
  await req.resp("Hello, World!",headers.newHttpHeaders())

proc dbHandler(req: Request) {.route("get","/db"),async.} = 
  
  let headers = {"Content-type": "application/json"}
  let i = rand(1..10000)
  let row = await conn.getRow(sql"select id,randomNumber from world where id=?", i)

  await req.resp($ %* {"id":row[0],"randomNumber":row[1]},headers.newHttpHeaders())

type QueryData = ref object
  id:string
  randomNumber:string

proc newQueryData(id:string;randomNumber:string):QueryData = 
  result = new QueryData
  result.id = id
  result.randomNumber = randomNumber

proc queriesHandler(req: Request) {.route("get","/queries"),async.} = 
  let headers = {"Content-type": "application/json"}
  var queries:string = ""
  var countNum:int
  try:
    queries = if req.query.len > 0 : req.query["queries"] else: ""
    countNum = queries.parseInt()
  except:
    countNum = 1

  if countNum < 1:
    countNum = 1
  elif countNum > 500:
    countNum = 500

  var response:seq[QueryData] = @[]
  echo countNum
  for _ in 1..countNum:
    let i = rand(1..10000)
    let row = await conn.getRow(sql"select id,randomNumber from world where id=?", i)
    response.add newQueryData(row[0],row[1])
  let data = $ %* response
  await req.resp(data,headers.newHttpHeaders())

proc fortunesHandler(req: Request) {.route("get","/fortunes"),async.} = 
  # https://github.com/TechEmpower/FrameworkBenchmarks/wiki/Project-Information-Framework-Tests-Overview#minimum-template
  let r = await conn.query(sql"select id,message from Fortune order by message asc")
  var rows = newSeq[Fortune]()
  for row in r.rows:
    rows.add newFortune(parseInt(row[0]),xmlEncode row[1])
 
  rows.add newFortune(0,"Additional fortune added at request time.")
  rows = rows.sortedByIt(it.message)
  let headers = {"Content-type": "text/html; charset=utf-8"}

  await req.resp(fortuneView(rows),headers.newHttpHeaders())

proc updatesHandler(req: Request) {.route("get","/updates"),async.} = 
  # https://github.com/TechEmpower/FrameworkBenchmarks/wiki/Project-Information-Framework-Tests-Overview#database-updates
  var queries:string = ""
  var countNum:int
  try:
    queries = if req.query.len > 0 : req.query["queries"] else: ""
    countNum = queries.parseInt()
  except:
    countNum = 1

  if countNum < 1:
    countNum = 1
  elif countNum > 500:
    countNum = 500

  var response:seq[QueryData] = @[]
  let up = await conn.prepare("update `world` set randomNumber=? where id = ?")
  let sel = await conn.prepare("select * from world where id=?")
  conn.transaction:
    for _ in 1..countNum:
      let i = rand(1..10000)
      let newRandomNumber = rand(1..10000)
      discard await conn.query(sel,i)
      discard await conn.query(up, newRandomNumber,i)
      response.add newQueryData($i,$newRandomNumber)
  await conn.finalize(up)
  await conn.finalize(sel)

  let headers = {"Content-type": "application/json"}
  await req.resp($ %* response,headers.newHttpHeaders())

when isMainModule:
  exitprocs.addExitProc proc() = waitFor conn.close()

  let address = "0.0.0.0:8080"
  let flags = {ReuseAddr}
  let r = newRouter[AsyncCallback]()
  r.addRoute(jsonHandler)
  r.addRoute(plaintextHandler)
  r.addRoute(dbHandler)
  r.addRoute(queriesHandler)
  r.addRoute(fortunesHandler)
  r.addRoute(updatesHandler)
  var server = newScorper(address, r, flags)
  server.start()
  
  waitFor server.join()
