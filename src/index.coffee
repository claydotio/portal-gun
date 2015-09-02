Promise = window.Promise or require 'promiz'

IS_FRAMED = window.self isnt window.top

REQUEST_TIMEOUT_MS = 2000

ERRORS =
  METHOD_NOT_FOUND: -32601
  INVALID_ORIGIN: 100
  DEFAULT: -1

ERROR_MESSAGES = {}
ERROR_MESSAGES[ERRORS.METHOD_NOT_FOUND] = 'Method not found'
ERROR_MESSAGES[ERRORS.INVALID_ORIGIN] = 'Invalid origin'
ERROR_MESSAGES[ERRORS.DEFAULT] = 'Error'

deferredFactory = ->
  resolve = null
  reject = null
  promise = new Promise (_resolve, _reject) ->
    resolve = _resolve
    reject = _reject
  promise.resolve = resolve
  promise.reject = reject

  return promise

isValidOrigin = (origin, trusted, allowSubdomains) ->
  unless trusted?
    return true

  for trust in trusted
    regex = if allowSubdomains
      new RegExp \
        "^https?://(\\w+\\.)?(\\w+\\.)?#{trust.replace(/\./g, '\\.')}/?$"
    else
      new RegExp "^https?://#{trust.replace(/\./g, '\\.')}/?$"

    if regex.test origin
      return true

  return false

###
# _portal is added to denote a portal-gun message
# RPCRequestAcknowledgement is to ensure the responder recieved the request
# RPCCallbackResponse is added to support callbacks for methods
#
# params, if containing a callback function, will have that method replaced
# with RPCCallback which should be used to emit callback responses
#
# Child {RPCRequest} -> Parent
#   Parent {RPCRequestAcknowledgement} -> Child
#   Parent {RPCResponse} -> Child
#
# Child {RPCRequest:{params:[RPCCallback]}} -> Parent
#   Parent {RPCRequestAcknowledgement} -> Child
#   Parent {RPCResponse} -> Child
#   Parent {RPCCallbackResponse} -> Child
#   Parent {RPCCallbackResponse} -> Child
#
# Parent {RPCError} -> Child

@typedef {Object} RPCRequest
@property {Boolean} _portal - Must be true
@property {String} id
@property {String} method
@property {Array<*>} params

@typedef {Object} RPCRequestAcknowledgement
@property {Boolean} _portal - Must be true
@property {String} id
@property {Boolean} acknowledge - must be true

@typedef {Object} RPCResponse
@property {Boolean} _portal - Must be true
@property {String} id
@property {*} result
@property {RPCError} error

@typedef {Object} RPCCallback
@property {Boolean} _portal - Must be true
@property {String} callbackId
@property {Boolean} _portalGunCallback - Must be true

@typedef {Object} RPCCallbackResponse
@property {Boolean} _portal - Must be true
@property {String} callbackId
@property {Array<*>} params

@typedef {Object} RPCError
@property {Boolean} _portal - Must be true
@property {Integer} code
@property {String} message
@property {Object} data - optional
###

class RPCClient
  constructor: ->
    @pendingRequests = {}
    @callbackFunctions = {}

  ###
  @param {Object} props
  @param {String} props.method
  @param {Array<*>} [props.params] - Functions are not allowed
  @returns RPCRequest
  ###
  createRPCRequest: do (lastRequestId = 0) ->
    ({method, params}) ->
      for param in params
        if typeof param is 'function'
          throw new Error 'Functions are not allowed. Use RPCCallback instead.'

      lastRequestId += 1
      id = String lastRequestId
      return {_portal: true, id, method, params}

  ###
  @returns RPCCallback
  ###
  createRPCCallback: do (lastCallbackId = 0) ->
    ->
      lastCallbackId += 1
      id = String lastCallbackId
      return {_portal: true, _portalGunCallback: true, callbackId: id}

  ###
  @param {Object} props
  @param {Array<*>} props.params
  @param {String} props.callbackId
  @returns RPCCallbackResponse
  ###
  createRPCCallbackResponse: ({params, callbackId}) ->
    return {_portal: true, callbackId: callbackId, params}

  ###
  @param {Object} props
  @param {String} props.responseId
  @returns RPCRequestAcknowledgement
  ###
  createRPCRequestAcknowledgement: ({requestId}) ->
    return {_portal: true, id: requestId, acknowledge: true}

  ###
  @param {Object} props
  @param {String} props.requestId
  @param {*} [props.result]
  @param {RPCError|Null} [props.error]
  @returns RPCResponse
  ###
  createRPCResponse: ({requestId, result, rPCError}) ->
    result ?= null
    rPCError ?= null
    return {_portal: true, id: requestId, result, error: rPCError}

  ###
  @param {Object} props
  @param {Errpr} [props.error]
  @returns RPCError
  ###
  createRPCError: ({code, data}) ->
    data ?= null
    message = ERROR_MESSAGES[code]
    return {_portal: true, code, message, data}

  isRPCEntity: (entity) -> entity?._portal
  isRPCRequest: (request) ->
    request?.id? and request.method?
  isRPCCallback: (callback) -> callback?._portalGunCallback
  isRPCResponse: (response) ->
    response?.id and (
      response.result isnt undefined or response.error isnt undefined
    )
  isRPCCallbackResponse: (response) ->
    response?.callbackId? and response.params?
  isRPCRequestAcknowledgement: (ack) -> ack?.acknowledge is true

  ###
  @param {String} method
  @param {Array<*>} [params]
  @returns {Promise}
  ###
  call: (method, reqParams = []) =>
    deferred = deferredFactory()
    params = []

    # replace callback params
    for param in reqParams
      if typeof param is 'function'
        callback = @createRPCCallback param
        @callbackFunctions[callback.callbackId] = param
        params.push callback
      else
        params.push param

    request = @createRPCRequest {method, params}

    @pendingRequests[request.id] = {
      reject: deferred.reject
      resolve: deferred.resolve
      isAcknowledged: false
    }

    try
      window.parent.postMessage JSON.stringify(request), '*'
    catch err
      deferred.reject err
      return deferred

    window.setTimeout =>
      unless @pendingRequests[request.id].isAcknowledged
        deferred.reject new Error 'Message Timeout'
    , REQUEST_TIMEOUT_MS

    return deferred

  ###
  @param {RPCResponse} rPCResponse
  ###
  resolveRPCResponse: (rPCResponse) ->
    request = @pendingRequests[rPCResponse.id]
    unless request?
      throw new Error 'Request not found'

    request.isAcknowledged = true

    {result, error} = rPCResponse
    if error?
      request.reject new Error error.message
    else if result?
      request.resolve result
    else
      request.resolve null
    return null

  ###
  @param {RPCRequestAcknowledgement} rPCRequestAcknowledgement
  ###
  resolveRPCRequestAcknowledgement: (rPCRequestAcknowledgement) ->
    request = @pendingRequests[rPCRequestAcknowledgement.id]
    unless request?
      throw new Error 'Request not found'

    request.isAcknowledged = true
    return null

  ###
  @param {RPCCallbackResponse} rPCCallbackResponse
  ###
  resolveRPCCallbackResponse: (rPCCallbackResponse) =>
    callbackFn = @callbackFunctions[rPCCallbackResponse.callbackId]
    unless callbackFn?
      throw new Error 'Callback not found'

    callbackFn.apply null, rPCCallbackResponse.params
    return null

  ###
  @param {RPCResponse|RPCCallbackResponse}
  ###
  resolveMessage: (message) =>
    if message.callbackId
      if not @callbacks[message.callbackId]
        return Promise.reject new Error 'Method not found'

      @callbacks[message.callbackId].apply null, message.params

    else
      if not @pendingMessages[message.id]
        return Promise.reject new Error 'Method not found'
      else
        @pendingMessages[message.id].acknowledged = true

        if message.acknowledge
          return Promise.resolve null
        else if message.error
          @pendingMessages[message.id].reject new Error message.error.message
        else
          if message.result?
            @pendingMessages[message.id].resolve message.result
          else
            @pendingMessages[message.id].resolve null


class PortalGun
  constructor: ->
    @config =
      trusted: null
      allowSubdomains: false
    @client = new RPCClient()
    @registeredMethods = {
      ping: -> 'pong'
    }

  ###
  # Bind global message event listener
  @param {Object} config
  @param {Array<String>|Null} config.trusted - trusted domains e.g.['clay.io']
  @param {Boolean} config.allowSubdomains - trust subdomains of trusted domain
  ###
  up: ({trusted, allowSubdomains} = {}) =>
    trusted ?= null
    allowSubdomains ?= false
    @config.trusted = trusted
    @config.allowSubdomains = allowSubdomains
    window.addEventListener 'message', @onMessage
    @validation = @client.call 'ping'

  # Remove global message event listener
  down: =>
    window.removeEventListener 'message', @onMessage

  ###
  @param {String} method
  @param {*} params - Arrays will be deconstructed as multiple args
  ###
  call: (method, params = []) =>

    # params should always be an array
    unless Object::toString.call(params) is '[object Array]'
      params = [params]

    localMethod = (method, params) =>
      fn = @registeredMethods[method]
      unless fn
        throw new Error 'Method not found'
      return fn.apply null, params

    if IS_FRAMED
      frameError = null
      @validation
      .then =>
        @client.call method, params
      .catch (err) ->
        frameError = err
        return localMethod method, params
      .catch (err) ->
        if err.message is 'Method not found' and frameError isnt null
          throw frameError
        else
          throw err
    else
      new Promise (resolve) ->
        resolve localMethod(method, params)

  onMessage: (e) =>
    reply = (message) ->
      e.source.postMessage JSON.stringify(message), '*'

    try # silent
      message = if typeof e.data is 'string' then JSON.parse(e.data) else e.data

      unless @client.isRPCEntity message
        throw new Error 'Non-portal message'

      if @client.isRPCRequest message
        method = message.method
        reqParams = message.params or []
        params = []

        # replace callback params with proxy functions
        for param in reqParams
          if @client.isRPCCallback param
            do (param) =>
              params.push (args...) =>
                reply @client.createRPCCallbackResponse {
                  params: args
                  callbackId: param.callbackId
                }
          else
            params.push param

        # acknowledge request, prevent request timeout
        reply @client.createRPCRequestAcknowledgement {requestId: message.id}

        @call method, params
        .then (result) =>
          reply @client.createRPCResponse {
            requestId: message.id
            result: result
          }
        .catch (err) =>
          reply @client.createRPCResponse {
            requestId: message.id
            rPCError: rPCError
          }
      else if @client.isRPCRequestAcknowledgement message
        if isValidOrigin e.origin, @config.trusted, @config.allowSubdomains
          @client.resolveRPCRequestAcknowledgement message
        else
          @client.resolveRPCResponse @client.createRPCResponse {
            requestId: message.id
            rPCError: @client.createRPCError {
              code: ERRORS.INVALID_ORIGIN
              data:
                origin: e.origin
            }
          }
      else if @client.isRPCResponse message
        if isValidOrigin e.origin, @config.trusted, @config.allowSubdomains
          @client.resolveRPCResponse message
        else
          @client.resolveRPCResponse @client.createRPCResponse {
            requestId: message.id
            rPCError: @client.createRPCError {
              code: ERRORS.INVALID_ORIGIN
              data:
                origin: e.origin
            }
          }
      else if @client.isRPCCallbackResponse message
        if isValidOrigin e.origin, @config.trusted, @config.allowSubdomains
          @client.resolveRPCCallbackResponse message
        else
          @client.resolveRPCCallbackResponse @client.createRPCCallbackResponse {
            callbackId: message.callbackId
            rPCError: @client.createRPCError {
              code: ERRORS.INVALID_ORIGIN
              data:
                origin: e.origin
            }
          }
      else
        throw new Error 'Unknown RPCEntity type'

  ###
  # Register method to be called on child request, or local request fallback

  @param {String} method
  @param {Function} fn
  ###
  on: (method, fn) =>
    @registeredMethods[method] = fn


portal = new PortalGun()
module.exports = {
  up: portal.up
  down: portal.down
  call: portal.call
  on: portal.on
}
