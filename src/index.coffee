Promise = window.Promise or require 'promiz'

IS_FRAMED = window.self isnt window.top

# If a response is not recieved within this time, consider the parent dead
REQUEST_TIMEOUT_MS = 1000

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
    regex = if allowSubdomains then \
       new RegExp '^https?://(\\w+\\.)?(\\w+\\.)?' +
                         "#{trust.replace(/\./g, '\\.')}/?$"
    else new RegExp '^https?://' +
                         "#{trust.replace(/\./g, '\\.')}/?$"

    if regex.test origin
      return true

  return false

###
# Messages follow the json-rpc 2.0 spec: http://www.jsonrpc.org/specification
# _portal is added to denote a portal-gun message
# RPCAcknowledgeRequest is added to ensure the responder recieved the request
# RPCCallbackResponse is added to support callbacks for methods


# params, if containing a callback function, will have that method replaced
# with: {_portalGunCallback: true, callbackId: {Number}}
# which should be used to emit callback responses

@typedef {Object} RPCRequest
@property {Integer} [id] - Without an `id` this is a notification
@property {String} method
@property {Array<*>} params
@property {Boolean} _portal - Must be true
@property {String} jsonrpc - Must be '2.0'


@typedef {Object} RPCAcknowledgeRequest
@property {Integer} id
@property {Boolean} acknowledge - pre-result response to notify requester
@property {Boolean} _portal - Must be true
@property {String} jsonrpc - Must be '2.0'


@typedef {Object} RPCResponse
@property {Integer} [id]
@property {*} result
@property {RPCError} error


@typedef {Object} RPCCallbackResponse
@property {Integer} callbackId
@property {Array} params


@typedef {Object} RPCError
@property {Integer} code
@property {String} message

###

class Poster
  constructor: ->
    @lastMessageId = 0
    @lastCallbackId = 0
    @pendingMessages = {}
    @callbacks = {}
    @isParentDead = false

  ###
  @param {String} method
  @param {Array} [params]
  @returns {Promise}
  ###
  postMessage: (method, reqParams = []) =>
    deferred = deferredFactory()
    params = []

    # callbacks
    for param in reqParams
      if typeof param is 'function'
        @lastCallbackId += 1
        id = @lastCallbackId
        @callbacks[id] = param
        params.push {_portalGunCallback: true, callbackId: id}
      else
        params.push param

    message = {method, params}

    try
      @lastMessageId += 1

      message.id = "#{@lastMessageId}"
      message._portal = true
      message.jsonrpc = '2.0'

      @pendingMessages[message.id] = {
        reject: deferred.reject
        resolve: deferred.resolve
        acknowledged: false
      }

      window.parent.postMessage JSON.stringify(message), '*'

    catch err
      deferred.reject err

    window.setTimeout =>
      unless @pendingMessages[message.id].acknowledged
        @isParentDead = true
        deferred.reject new Error 'Message Timeout'
    , REQUEST_TIMEOUT_MS

    if @isParentDead
      deferred.reject new Error 'Message Timeout'

    return deferred

  ###
  @param {RPCResponse|RPCCallbackResponse|RPCError}
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
          @pendingMessages[message.id].resolve message.result or null


class PortalGun
  constructor: ->
    @config =
      trusted: null
      allowSubdomains: false
    @poster = new Poster()
    @registeredMethods = {
      ping: -> 'pong'
    }

  ###
  # Bind global message event listener

  @param {Object} config
  @param {Array<String>} config.trusted - trusted domains e.g.['clay.io']
  @param {Boolean} config.allowSubdomains - trust subdomains of trusted domain
  ###
  up: ({trusted, allowSubdomains} = {}) =>
    trusted ?= null
    allowSubdomains ?= false
    @config.trusted = trusted
    @config.allowSubdomains = allowSubdomains
    window.addEventListener 'message', @onMessage

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
      @validateParent()
      .then =>
        @poster.postMessage method, params
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

  validateParent: =>
    @poster.postMessage 'ping'

  onMessage: (e) =>
    try
      message = if typeof e.data is 'string' then JSON.parse(e.data) else e.data

      if not message._portal
        throw new Error 'Non-portal message'

      isRequest = Boolean message.method

      if isRequest
        params = []
        {id, method} = message
        reqParams = message.params or []

        # callbacks
        for param in reqParams
          if param?._portalGunCallback
            params.push (params...) ->
              e.source.postMessage JSON.stringify({
                _portal: true
                jsonrpc: '2.0'
                callbackId: param.callbackId
                params
              }), '*'
          else
            params.push param

        # acknowledge request, prevent request timeout
        e.source.postMessage JSON.stringify({
          _portal: true
          jsonrpc: '2.0'
          id
          acknowledge: true
        }), '*'

        @call method, params
        .then (result) ->
          e.source.postMessage JSON.stringify({
            _portal: true
            jsonrpc: '2.0'
            id
            result
          }), '*'
        .catch (err) ->
          # json-rpc 2.0 error codes
          code = switch err.message
            when 'Method not found'
              -32601
            else
              -1

          e.source.postMessage JSON.stringify({
            _portal: true
            jsonrpc: '2.0'
            id: id
            error:
              code: code
              message: err.message
          }), '*'

      else
        if isValidOrigin e.origin, @config.trusted, @config.allowSubdomains
          @poster.resolveMessage message
        else
          @poster.resolveMessage {
            _portal: true
            jsonrpc: '2.0'
            id: message.id
            error:
              code: -1
              message: "Invalid origin #{e.origin}"
          }

    catch err
      return

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
