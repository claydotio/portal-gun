Promise = if Promise? then Promise else require 'promiz'
_map = require 'lodash/map'
_isEmpty = require 'lodash/isEmpty'

RPCClient = require './rpc_client'

DEFAULT_HANDSHAKE_TIMEOUT_MS = 10000 # 10 seconds
SW_CONNECT_TIMEOUT_MS = 3000 # 3s

selfWindow = if window? then window else self

class PortalGun
  ###
  @param {Object} config
  @param {Number} [config.timeout=3000] - request timeout (ms)
  @param {Function<Boolean>} config.isParentValidFn - restrict parent origin
  ###
  constructor: ({timeout, @handshakeTimeout, @isParentValidFn, useSw} = {}) ->
    @isParentValidFn ?= -> true
    timeout ?= null
    @handshakeTimeout ?= DEFAULT_HANDSHAKE_TIMEOUT_MS
    @isListening = false
    @isLegacy = false # TODO: remove when native apps are updated
    # window?._portalIsInAppBrowser is set by native app. on iOS it isn't set
    # soon enough, so we rely on userAgent
    isInAppBrowser = window?._portalIsInAppBrowser or
                      navigator.userAgent.indexOf('/InAppBrowser') isnt -1
    @hasParent = (window? and window.self isnt window.top) or isInAppBrowser
    @parent = window?.parent

    @client = new RPCClient({
      timeout: timeout
      postMessage: (msg, origin) =>
        if isInAppBrowser
          queue = try
            JSON.parse localStorage['portal:queue']
          catch
            null
          queue ?= []
          queue.push msg
          localStorage['portal:queue'] = JSON.stringify queue
        else
          @parent?.postMessage msg, origin
    })

    useSw ?= navigator.serviceWorker and window.location.protocol isnt 'http:'
    if useSw
      # only use service workers if current page has one
      @ready = new Promise (resolve, reject) ->
        readyTimeout = setTimeout resolve, SW_CONNECT_TIMEOUT_MS

        navigator.serviceWorker.ready
        .catch -> null
        .then (registration) =>
          worker = registration?.active
          if worker
            @sw = new RPCClient({
              timeout: timeout
              postMessage: (msg, origin) =>
                swMessageChannel = new MessageChannel()
                swMessageChannel?.port1.onmessage = (e) =>
                  @onMessage e, {isServiceWorker: true}
                worker.postMessage(
                  msg, [swMessageChannel.port2]
                )
            })
          clearTimeout readyTimeout
          resolve()
    else
      @ready = Promise.resolve true

    # All parents must respond to 'ping' with @registeredMethods
    @registeredMethods = {
      ping: => Object.keys @registeredMethods
    }
    @parentsRegisteredMethods = []

  setParent: (parent) =>
    @parent = parent
    @hasParent = true

  setInAppBrowserWindow: (@iabWindow, callback) =>
    # can't use postMessage, so this hacky executeScript works
    readyEvent = if navigator.userAgent.indexOf('iPhone') isnt -1 \
                 then 'loadstop' # for some reason need to wait for this on iOS
                 else 'loadstart'
    @iabWindow.addEventListener readyEvent, =>
      @iabWindow.executeScript {
        code: 'window._portalIsInAppBrowser = true;'
      }
      clearInterval @iabInterval
      @iabInterval = setInterval =>
        @iabWindow.executeScript {
          code: "localStorage.getItem('portal:queue');"
        }, (values) =>
          try
            values = JSON.parse values?[0]
            unless _isEmpty values
              @iabWindow.executeScript {
                code: "localStorage.setItem('portal:queue', '[]')"
              }
            _map values, callback
          catch err
            console.log err, values
      , 100
    @iabWindow.addEventListener 'exit', =>
      clearInterval @iabInterval

  replyInAppBrowserWindow: (data) =>
    escapedData = data.replace(/'/g, "\'")
    @iabWindow.executeScript {
      code: "
      if(window._portalOnMessage)
        window._portalOnMessage('#{escapedData}')
      "
    }

  onMessageInAppBrowserWindow: (data) =>
    @onMessage {
      data: data
      source:
        postMessage: (data) =>
          # needs to be defined in native
          @call 'browser.reply', {data}
    }

  # Binds global message listener
  # Must be called before .call()
  listen: =>
    @isListening = true
    selfWindow.addEventListener 'message', @onMessage

    # set via win.executeScript in cordova
    window?._portalOnMessage = (eStr) =>
      @onMessage {
        debug: true
        data: try
          JSON.parse eStr
        catch
          console.log 'error parsing', eStr
          null
      }

    @clientValidation = @client.call 'ping', null, {timeout: @handshakeTimeout}
    .then (registeredMethods) =>
      console.log 'got reg', registeredMethods
      if registeredMethods is 'pong'
        @isLegacy = true
      else if @hasParent
        @parentsRegisteredMethods = @parentsRegisteredMethods.concat(
          registeredMethods
        )

    @swValidation = @ready.then =>
      @sw.call 'ping', null, {timeout: @handshakeTimeout}
    .then (registeredMethods) =>
      @parentsRegisteredMethods = @parentsRegisteredMethods.concat(
        registeredMethods
      )

  close: =>
    @isListening = true
    selfWindow.removeEventListener 'message', @onMessage

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

    # TODO: clean this up
    @ready.then =>
      if @hasParent
        parentError = null
        @clientValidation
        .then =>
          if not @isLegacy and @parentsRegisteredMethods.indexOf(method) is -1
            return localMethod method, params
          else
            @client.call method, params
            .then (result) ->
              # need to send back methods for all parent frames
              if method is 'ping'
                localResult = localMethod method, params
                (result or []).concat localResult
              else
                result
            .catch (err) =>
              parentError = err
              if @sw
                @sw.call method, params
                .then (result) ->
                  # need to send back methods for all parent frames
                  if method is 'ping'
                    localResult = localMethod method, params
                    (result or []).concat localResult
                  else
                    result
                .catch ->
                  return localMethod method, params
              else
                return localMethod method, params
            .catch (err) ->
              if err.message is 'Method not found' and parentError isnt null
                throw parentError
              else
                throw err
      else
        new Promise (resolve) =>
          if @sw
            resolve(
              @swValidation.then =>
                if @parentsRegisteredMethods.indexOf(method) is -1
                  return localMethod method, params
                else
                  @sw.call(method, params)
                  .then (result) ->
                    # need to send back methods for all parent frames
                    if method is 'ping'
                      localResult = localMethod method, params
                      (result or []).concat localResult
                    else
                      result
                  .catch (err) ->
                    return localMethod method, params
            )
          else
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

    @call request.method, params...
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
          data: err
        }
      }

  onMessage: (e, {isServiceWorker} = {}) =>
    reply = (message) ->
      if window?
        e.source?.postMessage JSON.stringify(message), '*'
      else
        e.ports[0].postMessage JSON.stringify message

    try # silent
      message = if typeof e.data is 'string' then JSON.parse(e.data) else e.data

      unless RPCClient.isRPCEntity message
        throw new Error 'Non-portal message'

      if RPCClient.isRPCRequest message
        @onRequest(reply, message)
      else if RPCClient.isRPCEntity message
        if @isParentValidFn e.origin
          rpc = if isServiceWorker then @sw else @client
          rpc.resolve message
        else if RPCClient.isRPCResponse message
          rpc = if isServiceWorker then @sw else @client
          rpc.resolve RPCClient.createRPCResponse {
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
