Promise = window.Promise or require 'promiz'

RPCClient = require './rpc_client'

IS_FRAMED = window.self isnt window.top
HANDSHAKE_TIMEOUT_MS = 10 * 1000 # 10 seconds

class PortalGun
  ###
  @param {Object} config
  @param {Number} [config.timeout=3000] - request timeout (ms)
  @param {Function<Boolean>} config.isParentValidFn - restrict parent origin
  ###
  constructor: ({timeout, @isParentValidFn} = {}) ->
    @isParentValidFn ?= -> true
    timeout ?= null
    @isListening = false
    @client = new RPCClient({
      timeout: timeout
      postMessage: (msg, origin) ->
        window.parent?.postMessage msg, origin
    })
    # All parents must respond to 'ping' with 'pong'
    @registeredMethods = {
      ping: -> 'pong'
    }

  # Binds global message listener
  # Must be called before .call()
  listen: =>
    @isListening = true
    window.addEventListener 'message', @onMessage
    @validation = @client.call 'ping', null, {timeout: HANDSHAKE_TIMEOUT_MS}

  ###
  @param {String} method
  @param {...*} params
  @returns Promise
  ###
  call: (method, params...) =>
    unless @isListening
      return new Promise (resolve, reject) ->
        reject new Error 'Must call listen() before call()'

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

  onRequest: (reply, request) =>
    # replace callback params with proxy functions
    params = []
    for param in (request.params or [])
      if RPCClient.isRPCCallback param
        do (param) ->
          params.push (args...) ->
            reply RPCClient.createRPCCallbackResponse {
              params: args
              callbackId: param.callbackId
            }
      else
        params.push param

    # acknowledge request, prevent request timeout
    reply RPCClient.createRPCRequestAcknowledgement {requestId: request.id}

    @call request.method, params
    .then (result) ->
      reply RPCClient.createRPCResponse {
        requestId: request.id
        result: result
      }
    .catch (err) ->
      reply RPCClient.createRPCResponse {
        requestId: request.id
        rPCError: RPCClient.createRPCError {
          code: RPCClient.ERROR_CODES.DEFAULT
        }
      }

  onMessage: (e) =>
    reply = (message) ->
      e.source.postMessage JSON.stringify(message), '*'

    try # silent
      message = if typeof e.data is 'string' then JSON.parse(e.data) else e.data

      unless RPCClient.isRPCEntity message
        throw new Error 'Non-portal message'

      if RPCClient.isRPCRequest message
        @onRequest(reply, message)
      else if RPCClient.isRPCEntity message
        if @isParentValidFn e.origin
          @client.resolve message
        else if RPCClient.isRPCResponse message
          @client.resolve RPCClient.createRPCResponse {
            requestId: message.id
            rPCError: RPCClient.createRPCError {
              code: RPCClient.ERROR_CODES.INVALID_ORIGIN
            }
          }
        else
          throw new Error 'Invalid origin'
      else
        throw new Error 'Unknown RPCEntity type'
    catch err
      return

  ###
  # Register method to be called on child request, or local request fallback
  @param {String} method
  @param {Function} fn
  ###
  on: (method, fn) =>
    @registeredMethods[method] = fn

module.exports = PortalGun
