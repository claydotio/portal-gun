Promise = require 'promiz'

IS_FRAMED = window.self isnt window.top
ONE_SECOND_MS = 1000

class Poster
  constructor: ->
    @lastMessageId = 0
    @pendingMessages = {}

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
    , ONE_SECOND_MS

    return deferred

  resolveMessage: (message) ->
    if not @pendingMessages[message.id]
      return Promise.reject 'Method not found'

    else if message.error
      @pendingMessages[message.id].reject message.error

    else
      @pendingMessages[message.id].resolve message.result or null


class PortalGun
  constructor: ->
    @config =
      trusted: null
      subdomains: false
    @poster = new Poster()
    @registerdMethods = {
      ping: -> 'pong'
    }

  up: (config) =>
    @config = _.defaults config, @config
    window.addEventListener 'message', @onMessage

  down: =>
    window.removeEventListener 'message', @onMessage

  get: (method, params = []) =>
    localMethod = (method, params) =>
      fn = @registerdMethods[method] or -> throw new Error 'Method not found'
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

  register: (method, fn) =>
    @registerdMethods[method] = fn


portal = new PortalGun()
module.exports = {
  up: portal.up
  down: portal.down
  get: portal.get
  register: portal.register
}
