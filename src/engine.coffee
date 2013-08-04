MongoClient = require("mongodb").MongoClient
Server = require('mongodb').Server
debug = require("debug")("nongojobs:engine")
util = require("util")
EventEmitter = require("events").EventEmitter

initialId = new mongo.ObjectID("000000000000000000000000")

module.exports = class Engine extends EventEmitter
  
  constructor: (options) ->
    @options = options || {}
    @running = false
    @maxJobs = @options.maxJobs || 5
    @colName = options.colName
    @jobs = 0
    @subscribers = {}

  ensureConnection: (callback)->
    if @_db
      process.nextTick(-> callback(null, @_db))
    else if !@options.db
      process.nextTick(-> callback(new Error("Database connection information required")))
    else if typeof(@options.db) == "object"
      @_db = @options.db
      process.nextTick(-> callback(null, @_db))
    else if typeof(@options.db) == "string"
      MongoClient.connect(@options.db, @options.dbOptions (err, db)=>
        if err then return callback(err)
        @_db = db
        callback(null, @_db)
      )
    else
      process.nextTick(-> callback(new Error("Invalid database connection information")))

  cleanup: (job, callback)->
    @_db.collection(@options.dbCollection).update({_id: job._id}, {$set: {finished: true, locked: false}}, (err, result)->
      if err
        @emit("error", err)
      callback?()
    )

  unlock: (job, status, callback)->
    if typeof(status) == "function"
      callback = status
      status = {}
    status ?= {}
    status.locked = false
    @_db.collection(@options.dbCollection).findAndModify({_id: job._id, locked: true}, [], {$set: {status: status}}, (err, job)-> 
      # it will just remain locked if there is an error, will need manual inspection
      if err
        @emit("error", err)
      callback?()
    )

  update: (job, status, callback)->
    if typeof(status) == "function"
      callback = status
      status = {}
    @_db.collection(@options.dbCollection).update({_id: job._id}, {$set: {status: status}}, (err, job)->
      if err
        @emit("error", err)
      callback?()
    )

  start: =>
    if @stopping
      return debug("Stopping, will not run")
    if @running
      return debug("Already started")
    @running = true
    debug("running = true")
    from = initialId

    afterJob = =>
      @jobs--
      debug("#jobs = %d", @jobs)
      if @jobs == 0 && @stopping
        return @emit("stop")
      if @jobs < @maxJobs && !@stopping
        process.nextTick(check)

    check = =>
      if @stopping
        @running = false
        debug("running = false")
        return
      @_db.collection(@options.dbCollection).findAndModify({locked: false, finished: false, _id: {$gt: from}}, [], {$set: {locked: true}}, {new: true}, (err, job)=>
        if err
          @running = false
          debug("running = false")
          @emit("error", err)
          return
        if job
          from = job._id
          if @stopping
            @unlock(job)
            return
          @jobs++
          debug("Found job %j, #jobs = %d", util.inspect(job), @jobs)
          @process(job, (err, result)=>
            if err
              @emit("error", err)
              error = 
                message: err.message || err
                stack: err.stack || ""
              if result?.retry
                debug("Unlocking up %j", job)
                @unlock(job, {error: error}, afterJob)
              else
                @update(job, {error: error}, afterJob)
            else if !(result?.keep)
              debug("Cleaning up %j", job)
              @cleanup(job, afterJob)
          )
          if @jobs < @maxJobs && !@stopping
            process.nextTick(check)
        else
          @running = false
          debug("running = false")
          if @jobs == 0 && @stopping
            return @emit("stop")
      )

    @ensureConnection((err)->
      if err then return @emit(err)
      check()
    )

  stop: ->
    if !@stopping
      @stopping = true
      if @jobs == 0
        @emit("stop")

  process: (job, callback)->
    if @subscribers[job.type]
      debug("Forwarding %s to subscriber", job.type)
      @subscribers[job.type](job, callback)
    else
      process.nextTick(callback)
