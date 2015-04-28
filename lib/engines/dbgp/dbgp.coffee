parseString = require('xml2js').parseString
Q = require 'q'
{Emitter, Disposable} = require 'event-kit'

GlobalContext = require '../../models/global-context'
DebugContext = require '../../models/debug-context'
Watchpoint = require '../../models/watchpoint'

module.exports =
class Dbgp
  constructor: (options) ->
    @emitter = new Emitter
    @buffer = ''

  listening: ->
    return @server != undefined

  nextTransactionId: ->
    if !@transaction_id
      @transaction_id = 1
    return @transaction_id++

  running: ->
    return @socket && @socket.readyState == 1

  listen: (options) ->

    @promises = []
    @debugContext = new DebugContext
    net = require "net"
    console.log("listening")
    buffer = ''
    @server = net.createServer( (c) =>

      c.setEncoding('utf8');
      @socket = c;
      c.on 'data', @stuff
    ).listen 9000

  close: (options) ->
    unless !@socket
      @socket.end()
      delete @socket
    unless !@server
      @server.close()
      delete @server
    console.log("closed")

  parse: (buffer) =>
    while buffer.split("\0").length >= 2
      n = buffer.indexOf("\0")
      len = parseInt(buffer.slice(0, n))
      message = buffer.slice(n+1, n+1+len)
      buffer = buffer.slice(n+2+len)
      o = parseString message, (err, result) =>
        type = Object.keys(result)[0]
        switch type
          when "init" then @onInit result
          when "response" then @parseResponse result
    return buffer

  parseResponse: (data) =>
    console.log "Parsing response"
    console.dir data
    result = data.response.$
    transactionId = result.transaction_id
    # if data.response.$.status == "break"
    #   console.log "A break!"
      #@notifyResponseBreak data
    # if data.response.$.command == "context_get"
    #   context = @buildContext(data)
    #   @notifyContextChange(context)

    if @promises[transactionId] != undefined
      console.log "Promise fulfilled for transaction " + transactionId
      @promises[transactionId].resolve(data)
      delete @promises[transactionId]
    else
      console.warning "Could not find promise for transaction " + transactionId


  stuff: (data) =>
    console.log(data)
    message = @parse(data)
    # @getFeature('language_supports_threads')

  command: (command, options, data) =>

    transactionId = @nextTransactionId()
    deferred = Q.defer();
    @promises[transactionId] = deferred

    payload = command + " -i " + transactionId
    if options && Object.keys(options).length > 0
      argu = ("-"+arg + " " + val for arg, val of options)
      argu2 = argu.join(" ")
      payload += " " + argu2
    if data
      payload += + " -- " + new Buffer(data, 'ascii').toString('base64')
    if @socket
      @socket.write(payload + "\0")
    console.log payload
    return deferred.promise

  getFeature: (feature_name) =>
    @command("feature_get", {n: feature_name})

  setFeature: (feature_name, value) =>
    @command("feature_set", {n: feature_name, v: value})

  onInit: (data) =>
    @sendAllBreakpoints()
    .then () =>
      return @continue("run")
    .then () =>
      return @getContextNames()
    .then (data) =>
      return @processContextNames(data)
    .then () =>
      console.dir @debugContext
      return @notifyDebugContextChange(@debugContext)


  sendAllBreakpoints: ->
    breakpoints = GlobalContext.getBreakpoints()
    commands = []
    for breakpoint in breakpoints
      options = {
        t: 'line',
        f: breakpoint.getPath(), #'file://C:/Users/gabriel/Documents/test.php',
        n: breakpoint.getLine()
      }
      commands.push @command("breakpoint_set", options)
    return Q.all(commands)

  continue: (type) ->
    return @command(type)

  getContextNames: () ->
    console.log "getting context names"
    return @command("context_names")

  processContextNames: (data) =>
    console.log "Context names: "
    console.dir data
    @debugContext.clear()
    for context in data.response.context
      console.dir context
      @debugContext.addScope(context.$.id,context.$.name)

    commands = []
    scopes = @debugContext.getScopes()
    for index, scope of scopes
      commands.push @updateContext (scope)

    # for watchpoint in GlobalContext.getWatchpoints
    #   commands.push @evalWatchpoint(watchpoint)
    console.dir commands
    return Q.all(commands)


  evalWatchpoint: (watchpoint) ->

    return @command("eval", null, watchpoint.getExpression())
    .then (data) ->
      console.log "The data with the eval is: "
      console.dir data
      @debugContext.setWatchpointValue(watchpoint, data)

  updateContext: (scope) =>
    p = @contextGet(scope.scopeId)
    return p.then (data) =>
      console.log("this does run")
      context = @buildContext data
      console.log("this doesn't run");
      console.dir context
      console.dir scope
      @debugContext.setScopeContext(scope.scopeId, context)
      console.log 'resolving'

  contextGet: (scope) =>
    return @command("context_get", {c: scope})


  buildContext: (response) =>
    data = {}
    data.type = 'context'
    data.context = response.response.$.context
    data.variables = []
    for property in response.response.property
      v = @parseContextVariable(property)
      data.variables.push v
    return data

  parseContextVariable: (variable) ->
    datum = {
      name : variable.$.name
      fullname : variable.$.fullname
    }
    datum.type = variable.$.type
    switch variable.$.type
      when "string"
        switch variable.$.encoding
          when "base64"
            datum.value = new Buffer(variable._, 'base64').toString('ascii')
          else
            console.error "Unhandled context variable encoding: " + variable.$.encoding
      when "array"
        datum.value = []
        if variable.property
          for property in variable.property
            datum.value.push @parseContextVariable(property)
      when "uninitialized"
        datum.value = undefined
      else
        console.error "Unhandled context variable type: " + variable.$.type
    return datum

  # events
  onDebugContextChange: (callback) ->
    @emitter.on 'php-debug.debugContextChange', callback

  notifyDebugContextChange: (data) ->
    console.log "notifying debug context change"
    @emitter.emit 'php-debug.debugContextChange', data

  onResponseBreak: (callback) ->
    @emitter.on 'php-debug.responseBreak', callback

  notifyResponseBreak: (type, data) ->
    console.log "Emitting response break"
    @emitter.emit 'php-debug.responseBreak', data