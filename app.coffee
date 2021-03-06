# Setup
express = require('express')
MongoClient = require('mongodb').MongoClient
assert = require('assert')
Db = require('mongodb').Db
Server = require('mongodb').Server
Connection = require('mongodb').Connection
http = require('http')
debug = require('util').debug
inspect = require('util').inspect
bodyParser = require('body-parser')
socketio = require('socket.io')

app = express()

app.use bodyParser.json()
app.use bodyParser.urlencoded(extended: true)

app.use express.static(__dirname + '/public')
app.set 'view engine', 'ejs'

# MongoDB
host = 'localhost'
port = 27017
mongourl = process.env.MONGOHQ_URL or process.env.MONGODB_URL or 'mongodb://' + host + ':' + port + '/clickityclack'
db = undefined

MongoClient.connect mongourl, (error, database) ->
  if error
    throw error
  db = database

# Homepage
app.get '/', (request, response) ->
  response.render 'index'

# Create a new event
app.post '/create', (request, response) ->
  if isNaN(request.body.cap) or request.body.name == ''
    return response.json('error': -1)
  newEvent =
    '_id': randomString()
    'name': request.body.name
    'count': 0
    'cap': request.body.cap
    'public': request.body.public
    'date': new Date()
  db.collection 'events', (error, collection) ->
    collection.insert newEvent, { w: 1 }
  response.json newEvent

# Get all events (JSON)
app.get '/events/get', (request, response) ->
  db.collection 'events', (error, collection) ->
    collection.find({public: true}, { _id: 0 }).toArray (error, items) ->
      if items == null
        response.json 'error': -1
      else
        items.reverse()
        response.json items

# Get an event
app.get '/:event/get', (request, response) ->
  db.collection 'events', (error, collection) ->
    collection.findOne { _id: request.params.event }, (error, item) ->
      if item == null
        response.json 'error': -1
      else
        response.json item

# Increment an event
app.post '/:event/increment', (request, response) ->
  db.collection 'events', (error, collection) ->
    collection.findOne { _id: request.params.event }, (error, item) ->
      if item == null
        response.json 'error': -1
      else if item.count < item.cap
        collection.update { _id: request.params.event }, { $inc: count: 1 }, (error, numberOfUpdatedObjects) ->
          collection.findOne { _id: request.params.event }, (error, item) ->
            pushUpdate request.params.event, item.count
            response.json item
      else
        response.json item

# Decrement an event
app.post '/:event/decrement', (request, response) ->
  db.collection 'events', (error, collection) ->
    collection.findOne { _id: request.params.event }, (error, item) ->
      if item == null
        response.json 'error': -1
      else if item.count > 0
        collection.update { _id: request.params.event }, { $inc: count: -1 }, (error, numberOfUpdatedObjects) ->
          collection.findOne { _id: request.params.event }, (error, item) ->
            pushUpdate request.params.event, item.count
            response.json item
      else
        response.json item

# view all events
app.get '/events', (request, response) ->
  db.collection 'events', (error, collection) ->
    collection.find({public: true}).toArray (error, items) ->
      if items == null
        response.json 'error': -1
      else
        items.reverse()
        response.render 'events', items: items

# View an event
app.get '/:event', (request, response) ->
  db.collection 'events', (error, collection) ->
    collection.findOne { _id: request.params.event }, (error, item) ->
      if item == null
        response.json 'error': -1
      else
        response.render 'event', item: item

# Express web server
webport = process.env.PORT or 3000
server = app.listen(webport, ->
  `var port`
  `var host`
  host = server.address().address
  port = server.address().port
  console.log 'ClickityClack listening at http://%s:%s', host, port
)

serversocket = socketio.listen(server)
serversocket.on 'connection', (socket) ->
  socket.on 'join', (request) ->
    socket.join(request.event)

  socket.on 'increment', (request) ->
    db.collection 'events', (error, collection) ->
      collection.findOne { _id: request.event }, (error, item) ->
        if item != null && item.count < item.cap
          collection.update { _id: request.event }, { $inc: count: 1 }, (error, numberOfUpdatedObjects) ->
            collection.findOne { _id: request.event }, (error, item) ->
              pushUpdate request.event, item.count

  socket.on 'decrement', (request) ->
    db.collection 'events', (error, collection) ->
      collection.findOne { _id: request.event }, (error, item) ->
        if item != null && item.count > 0
          collection.update { _id: request.event }, { $inc: count: -1 }, (error, numberOfUpdatedObjects) ->
            collection.findOne { _id: request.event }, (error, item) ->
              pushUpdate request.event, item.count

pushUpdate = (event, count) ->
  serversocket.to(event).emit 'update', count: count

# Additional functions
randomString = ->
  length = 7
  chars = '0123456789abcdefghijklmnopqrstuvwxyz'
  result = ''
  i = length
  while i > 0
    result += chars[Math.round(Math.random() * (chars.length - 1))]
    --i
  result
