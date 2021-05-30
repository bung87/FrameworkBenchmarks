import std / [macros,random,json,strformat,os,cgi,strutils,algorithm,nativesockets,exitprocs]
import scorper
import amysql
import amysql / async_pool
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


let poolSize = 512

var conn{.threadvar.}:AsyncPoolRef

var lock {.threadvar.}:AsyncLock
lock = newAsyncLock()

conn = waitFor newAsyncPool(DB_DSN,poolSize)

type AsyncCallback = proc (request: Request): Future[void] {.closure, gcsafe, raises: [].}

proc jsonHandler(req: Request) {.route("get","/json"),async.} = 
  var headers = {"Content-type": "application/json"}
  await req.resp("""{"message":"Hello, World!"}""",headers.newHttpHeaders())

proc plaintextHandler(req: Request) {.route("get","/plaintext"),async.} = 
  var headers = {"Content-type": "text/plain"}
  await req.resp("Hello, World!",headers.newHttpHeaders())

proc dbHandler(req: Request) {.route("get","/db"),async.} = 
  var headers = {"Content-type": "application/json"}
  let i = rand(1..10000)
  # await lock.acquire()
  # echo conn.hasFreeConn()
  let row = await conn.getRow(sql"select id,randomNumber from world where id=?", i)
  # lock.release()
  await req.resp($ %* {"id":parseInt row[0],"randomNumber":parseInt(row[1]) },headers.newHttpHeaders())

type QueryData = ref object
  id:int
  randomNumber:int

proc newQueryData(id:int;randomNumber:int):QueryData = 
  result = new QueryData
  result.id = id
  result.randomNumber = randomNumber

proc queriesHandler(req: Request) {.route("get","/queries"),async.} = 
  var headers = {"Content-type": "application/json"}
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
  var row:seq[string]
  var i:int
  
  for _ in 1..countNum:
    i = rand(1..10000)
    echo conn.hasFreeConn(),$i
    try:
      # await lock.acquire()
      row = await conn.getRow(sql"select id,randomNumber from world where id=?", i)
      # lock.release()
      response.add newQueryData(parseInt row[0],parseInt row[1])
    except Exception as e:
      echo e.msg
      quit(1)
    
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

  conn.withConn(conn2):
    conn2.transaction:
      for _ in 1..countNum:
        let i = rand(1..10000)
        let newRandomNumber = rand(1..10000)
        discard await conn2.exec(sql"select * from world where id=?",$i)
        discard await conn2.exec(sql"update `world` set randomNumber=? where id = ?", $newRandomNumber,$i)
        response.add newQueryData(i,newRandomNumber)

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
