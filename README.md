# nongojobs

Job engine in (No)de.js and M(ongo)DB

## Overview

This small job engine polls a MongoDB collection for new jobs. It stops when no more jobs are found and it must be restarted in order to handle future jobs. This can be easily done with a job scheduler such as [cron](https://github.com/ncb000gt/node-cron).

A job is defined by a single MongoDB document. Jobs are routed to handlers (local functions) by their `type` field.

### Features

* Easily scalable, more than one Nodejs processes running engines can be started.
* Synchronization is achieved with MongoDB atomic updates (findAndModify). No coordination servers are needed to avoid handling the same job more than once.
* More than one engine can run in the same process.
* Can configure the maximum number of concurrent jobs managed by the same engine instance.
* Handlers can forward their jobs to other servers.
* Errors from the handlers are saved in the database, attached to the job document.
* Can either delete or keep jobs in the database for inspection if requested by the handler.
* Can retry jobs if requested by the handler.

## Installation

`npm install nongojobs`

## Usage

To instantiate an `Engine` that will run until no more jobs are found:

```javascript
var Engine = require("nongojobs").Engine;
var jobs = new Engine(options);
jobs.subscribers["EMAIL"] = new EmailSender();
jobs.run();
```

### Options

_maxJobs_ : integer, maximum number of concurrent jobs. Default 5.
_colName_ : string, the collection where the jobs are stored.
_db_ : either a mongodb-native instance of database or a connection string for MongoClient.
_dbOptions_, if _db_ is a connection string : further options to be passed to MongoClient.connect.

### Methods

_start_ : starts to check for jobs. It will stop checking when there are no jobs in the database or `stop` is called.
_stop_ : finish handling all active jobs and stop checking for new jobs. When all active jobs are finished, the _stop_ event is triggered.

### Events

_error_ : Called when an error has been encountered, including errors from handlers.
_stop_ : Triggered after calling `stop` and all active jobs have been handled.

### Handlers

Handlers are simple Node-style functions. 

```javascript
function handler (job, callback) { 
  console.log(job.type); 
}
```

Handlers are attached in a very simple way, using the property `subscribers`. 

```javascript
jobs.subscribers[<type>] = function(job, callback) { 
  console.log(job.type);
  process.nextTick(callback);
};
```

Replace `<type>` with a unique identifier of the job type. Uniqueness is not enforced on this field, but the engine will forward all jobs of the same type to the same handler.

For example, to handle emails:

```javascript
jobs.subscribers["EMAIL"] = function(job, callback) { 
  emails.send("john@doe.com", "What's up?", callback);
};
```

Only one handler can be attached to a type. If you need to create some logic based on a subcategory of the type, just attach other properties to the job when inserting it in the database and write the logic in the handler.

For example, if you want to send several types of emails:

```javascript
jobs.subscribers["EMAIL"] = function(job, callback) { 
  if (job.emailType === "WELCOME")
    emails.send("john@doe.com", "Hello John Doe!", callback);
  else
    emails.send("john@doe.com", "What's up?", callback);
};
```

### Keep and retry

If there's an error while handling the jobs, the handler should return the error as the first parameter of `callback`, following Node's convention. In this case, the default behavior for the job engine is to keep the job locked and not retry it later. If you wish to retry the job later, pass `{retry: true}` as the second parameter to `callback`. Errors are attached to the job document in the database.

If there is no error, the default action is to delete the job from the database. If you wish to keep the job in the database, just pass `{keep: true}` as the second parameter to `callback`. The same job will not be handled more than once.

### How do I check for jobs periodically?

Call start periodically. Use timeouts, intervals, or another solution like [cron](https://github.com/ncb000gt/node-cron). If the jobs are inserted at a rate faster than the engine can handle them then the engine never stops checking for new jobs. It only stops checking when there are no jobs to handle. There is no problem if you call `start` several times, if the engine is already started it will do nothing.

#### Using intervals

```javascript
setInterval(function(){
  jobs.start();
}, 60000);
```

#### Using [cron](https://github.com/ncb000gt/node-cron)

```javascript
CronJob = require("cron").CronJob;
new CronJob("0 * * * * *", jobs.start, null, true);
```

### How to create jobs

Just insert them into the MongoDB collection using any MongoDB driver on any platform. At least the following fields must be set:

```javascript
{
  type: <type> //any string
  locked: false
  finished: false
}
```

### Indexes

The following indexes should be manually created on the jobs collection:

{locked: 1, finished: 1, _id: 1}

## TODO

* Tests.
* Ensure that necessary indexes exist.

## License

(The MIT License)

Copyright (c) 2013 Mihnea Scafes &lt;mihnea@nagemus.com&gt;

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
