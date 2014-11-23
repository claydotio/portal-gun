# TODO: Callbacks
Promise = require 'promiz'

IS_FRAMED = window.self isnt window.top
ONE_SECOND_MS = 1000


###
# Messages follow the json-rpc 2.0 spec: http://www.jsonrpc.org/specification
# _portal is added to denote a portal-gun message

@typedef {Object} RPCRequest
@property {Integer} [id] - Without an `id` this is a notification
@property {String} method
@property {Array<*>} params
@property {Boolean} _clay - Must be true
@property {String} jsonrpc - Must be '2.0'

@typedef {Object} RPCResponse
@property {Integer} [id]
@property {*} result
@property {RPCError} error

@typedef {Object} RPCError
@property {Integer} code
@property {String} message

###

class Poster
  constructor: (@timeout) ->
    @lastMessageId = 0
    @pendingMessages = {}

  setTimeout: (@timeout) => null

  ###
  @param {String} method
  @param {Array} [params]
  @returns {Promise}
  ###
  postMessage: (method, params = []) =>
    deferred = new Promise (@resolve, @reject) => null
    message = {method, params}

    try
      @lastMessageId += 1
      id = @lastMessageId

      message.id = id
      message._portal = true
      message.jsonrpc = '2.0'

      @pendingMessages[message.id] = deferred

      window.parent.postMessage JSON.stringify(message), '*'

    catch err
      deferred.reject err

    window.setTimeout ->
      deferred.reject new Error 'Message Timeout'
    , @timeout

    return deferred

  ###
  @param {RPCResponse|RPCError}
  ###
  resolveMessage: (message) ->
    if not @pendingMessages[message.id]
      return Promise.reject 'Method not found'

    else if message.error
      @pendingMessages[message.id].reject new Error message.error.message

    else
      @pendingMessages[message.id].resolve message.result or null


class PortalGun
  constructor: ->
    @config =
      trusted: null
      subdomains: false
      timeout: ONE_SECOND_MS
    @poster = new Poster timeout: @config.timeout
    @registeredMethods = {
      ping: -> 'pong'
    }

  ###
  # Bind global message event listener

  @param {Object} config
  @param {String} config.trusted - trusted domain name e.g. 'clay.io'
  @param {Boolean} config.subdomains - trust subdomains of trusted domain
  @param {Number} config.timeout - global message timeout
  ###
  up: ({trusted, subdomains, timeout} = {}) =>
    if trusted isnt undefined
      @config.trusted = trusted
    if subdomains?
      @config.subdomains = subdomains
    if timeout?
      @config.timeout = timeout
    @poster.setTimeout @config.timeout
    window.addEventListener 'message', @onMessage

  # Remove global message event listener
  down: =>
    window.removeEventListener 'message', @onMessage

  ###
  @param {String} method
  @param {Array} [params]
  ###
  get: (method, params = []) =>

    # params should always be an array
    unless Object::toString.call(params) is '[object Array]'
      params = [params]

    localMethod = (method, params) =>
      fn = @registeredMethods[method] or -> throw new Error 'Method not found'
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

  isValidOrigin: (origin) =>
    unless @config?.trusted
      return true

    regex = if @config.subdomains then \
       new RegExp '^https?://(\\w+\\.)?(\\w+\\.)?' +
                         "#{@config.trusted.replace(/\./g, '\\.')}/?$"
    else new RegExp '^https?://' +
                         "#{@config.trusted.replace(/\./g, '\\.')}/?$"

    return regex.test origin

  onMessage: (e) =>
    try
      message = JSON.parse e.data

      if not message._portal
        throw new Error 'Non-portal message'

      isResponse = message.result or message.error
      isRequest = !!message.method

      if isResponse
        unless @isValidOrigin e.origin
          message.error = {message: "Invalid origin #{e.origin}", code: -1}

        @poster.resolveMessage message

      else if isRequest
        {id, method, params} = message

        @get method, params
        .then (result) ->
          message = {id, result, _portal: true, jsonrpc: '2.0'}
          e.source.postMessage JSON.stringify(message), '*'

        .catch (err) ->

          # json-rpc 2.0 error codes
          code = switch err.message
            when 'Method not found'
              -32601
            else
              -1

          message =
            _portal: true
            jsonrpc: '2.0'
            id: id
            error:
              code: code
              message: err.message

          e.source.postMessage JSON.stringify(message), '*'

      else
        throw new Error 'Invalid message'

    catch err
      console.log err
      return

  ###
  # Register method to be called on child request, or local request fallback

  @param {String} method
  @param {Function} fn
  ###
  register: (method, fn) =>
    @registeredMethods[method] = fn


portal = new PortalGun()
module.exports = {
  up: portal.up
  down: portal.down
  get: portal.get
  register: portal.register
}
