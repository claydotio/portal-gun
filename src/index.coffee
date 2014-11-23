Promise = require 'promiz'

IS_FRAMED = window.self isnt window.top
ONE_SECOND_MS = 1000

class Poster
  constructor: ({@isValidOrigin}) ->
    @isValidOrigin ?= -> true
    @lastMessageId = 0
    @pendingMessages = {}

  postMessage: (method, params) =>
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

  onMessage: (e) =>
    try
      message = JSON.parse e.data
      id = message.id

      unless message._portal
        throw new Error 'Non-portal message'

      unless @pendingMessages[id]
        throw new Erro 'Pending not found'

      unless @isValidOrigin e.origin
        return @pendingMessages[id].reject \
          new Error "Invalid origin #{e.origin}"

      if message.error
        @pendingMessages[message.id].reject message.error
      else
        @pendingMessages[message.id].resolve message.result

    catch err
      return


class PortalGun
  constructor: ->
    @config =
      trusted: null
      subdomains: false
    @poster = new Poster(isValidOrigin: @isValidOrigin)


  get: (method, params = []) =>
    localMethod = (method, params) ->
      return methodToFn(method).apply null, params

    if IS_FRAMED
      frameError = null
      @validateParent()
      .then =>
        @poster.postMessage method, params
      .catch (err) ->
        frameError = err
        return localMethod({method, params})
      .catch (err) ->
        if err.message is 'Method not found' and frameError isnt null
          throw frameError
        else
          throw err
    else
      new Promise (resolve) ->
        resolve localMethod(method, params)

  validateParent: ->
    @poster.postMessage 'ping'

  isValidOrigin: (origin) =>
    unless @config.trusted
      return true

    if @config.subdomains
      regex = new RegExp '^https?://(\\w+\\.)?(\\w+\\.)?' +
                         "#{@config.trusted.replace(/\./g, '\\.')}/?$"
      return regex.test origin

    else
      regex = new RegExp '^https?://' +
                         "#{@config.trusted.replace(/\./g, '\\.')}/?$"
      return regex.test origin

  up: (config) ->
    @config = _.defaults config, @config
    window.addEventListener 'message', @poster.onMessage

  down: ->
    window.removeEventListener 'message', @poster.onMessage



module.exports = new PortalGun()

methodToFn = (method) ->
  switch method
    when 'share.any' then shareAny
    else -> throw new Error 'Method not found'
