require './polyfill'

_ = require 'lodash'
rewire = require 'rewire'
Promise = require 'bluebird'
b = require 'b-assert'

PortalGun = require '../src/index'
RPCClient = require '../src/rpc_client'

withParent = ({methods, origin}, fn) ->
  oldPost = window.parent?.postMessage
  window.parent?.postMessage = (msg) ->
    req = JSON.parse msg
    b RPCClient.isRPCRequest req
    reply = (message) ->
      e = document.createEvent 'Event'
      e.initEvent 'message', true, true
      e.origin = origin
      e.data = JSON.stringify message
      window.dispatchEvent e

    # replace callback params with proxy functions
    params = []
    for param in req.params
      if RPCClient.isRPCCallback param
        do (param) ->
          params.push (args...) ->
            reply RPCClient.createRPCCallbackResponse {
              params: args
              callbackId: param.callbackId
            }
      else
        params.push param

    new Promise (resolve) ->
      resolve methods[req.method](params...)
    .then (result) ->
      reply RPCClient.createRPCResponse {
        requestId: req.id
        result: result
      }
    .catch (err) ->
      reply RPCClient.createRPCResponse {
        requestId: req.id
        rPCError: RPCClient.createRPCError {code: -1}
      }

  new Promise (resolve) ->
    resolve fn()
  .then ->
    window.parent?.postMessage = oldPost
  .catch (err) ->
    window.parent?.postMessage = oldPost
    throw err


childCall = (request, cb) ->
  e = document.createEvent 'Event'
  e.initEvent 'message', true, true
  e.data = JSON.stringify RPCClient.createRPCRequest request
  e.source =
    postMessage: (msg) ->
      res = JSON.parse msg
      cb(res)

  window.dispatchEvent e


describe 'portal-gun', ->
  describe 'listen()', ->
    it 'listens', ->
      withParent {
        methods:
          ping: -> 'pong'
      }, ->
        portal = new PortalGun()
        portal.listen()
        portal.close()

  describe 'call()', ->
    it 'requires listening before calling', (done) ->
      portal = new PortalGun()
      portal.call 'ping'
      .catch (err) ->
        portal.close()
        b err.message, 'Must call listen() before call()'
        done()

    it 'calls method on parent frame', ->
      withParent {
        methods:
          ping: -> 'pong'
      }, ->
        portal = new PortalGun()
        portal.listen()
        portal.call 'ping'
        .then (pong) ->
          portal.close()
          b pong, 'pong'

    it 'calls method with multiple parameters', ->
      withParent {
        methods:
          ping: -> 'pong'
          paramer: (one, two) -> [one, two]
      }, ->
        portal = new PortalGun()
        portal.listen()
        portal.call 'paramer', 'one', 'two'
        .then (res) ->
          portal.close()
          b res, ['one', 'two']

    it 'recieves errors from parent frame', ->
      withParent {
        methods:
          ping: -> 'pong'
          ding: -> throw new Error 'dong'
      }, ->
        new Promise (resolve) ->
          portal = new PortalGun()
          portal.listen()
          portal.call 'ding'
          .catch (err) ->
            portal.close()
            b err.message, 'Error'
            resolve()

    # https://github.com/claydotio/portal-gun/issues/3
    it 'recieves false from parent frame', ->
      withParent {
        methods:
          ping: -> 'pong'
          f: -> false
      }, ->
        portal = new PortalGun()
        portal.listen()
        portal.call 'f'
        .then (f) ->
          portal.close()
          b f, false

    it 'times out when no response from parent', ->
      withParent {
        methods:
          ping: -> 'pong'
          timeout: ->
            new Promise -> null
      }, ->
        new Promise (resolve) ->
          portal = new PortalGun({timeout: 10})
          portal.listen()
          portal.call 'timeout'
          .catch (err) ->
            portal.close()
            b err.message, 'Message Timeout'
            resolve()

    it 'calls method with callback', ->
      withParent {
        methods:
          ping: -> 'pong'
          cb: (fn) ->
            fn('xxx')
            null
      }, ->
        new Promise (resolve) ->
          portal = new PortalGun()
          portal.listen()
          portal.call 'cb', (res) ->
            portal.close()
            b res, 'xxx'
            resolve()

    it 'calls method with callback with multiple params', (done) ->
      withParent {
        methods:
          ping: -> 'pong'
          cb: (fn) ->
            fn('xxx', 'yyy')
            null
      }, ->
        portal = new PortalGun()
        portal.listen()
        portal.call 'cb', (xxx, yyy) ->
          portal.close()
          b xxx, 'xxx'
          b yyy, 'yyy'
          done()

    it 'succeeds on valid domains', ->
      withParent {
        origin: 'abc'
        methods:
          ping: -> 'pong'
          sensitive: -> 'secret'
      }, ->
        portal = new PortalGun({
          isParentValidFn: (origin) ->
            b origin, 'abc'
            return true
        })
        portal.listen()
        portal.call 'sensitive'
        .then (res) ->
          portal.close()
          b res, 'secret'

    it 'fails on invalid domains', ->
      withParent {
        origin: 'abc'
        methods:
          ping: -> 'pong'
          sensitive: -> 'xxx'
      }, ->
        portal = new PortalGun({
          isParentValidFn: (origin) ->
            if origin is 'abc'
              return false
            return true
        })
        portal.listen()
        portal.on 'sensitive', -> 'secret'
        portal.call 'sensitive'
        .then (res) ->
          b res, 'secret'
          new Promise (resolve, reject) ->
            portal.call 'missing'
            .then reject
            .catch (err) ->
              portal.close()
              b err.message, 'Invalid origin'
              resolve()
            .catch reject

  describe 'on()', ->
    it 'responds to ping', (done) ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()

      childCall {method: 'ping', params: []}, (res) ->
        if RPCClient.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          portal.close()
          b wasAcknoleged, true
          b RPCClient.isRPCResponse res
          b res.result, 'pong'
          done()

    # https://github.com/claydotio/portal-gun/issues/6
    it 'passes params correctly', ->
      withParent {
        methods:
          ping: -> 'pong'
      }, ->
        new Promise (resolve, reject) ->
          wasAcknoleged = false
          portal = new PortalGun({timeout: 0})
          portal.listen()
          portal.on 'parama', (a, b) -> [a, b]

          childCall {method: 'parama', params: ['a', 'b']}, (res) ->
            if RPCClient.isRPCRequestAcknowledgement res
              wasAcknoleged = true
            else
              portal.close()
              resolve {res, wasAcknoleged}
        .then ({res, wasAcknoleged}) ->
          b wasAcknoleged, true
          b RPCClient.isRPCResponse res
          b res.result, ['a', 'b']

    it 'acknowledges immediately', (done) ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'long', ->
        new Promise -> null

      childCall {method: 'long', params: []}, (res) ->
        if RPCClient.isRPCRequestAcknowledgement res
          done()

    it 'sends request up', ->
      withParent {
        methods:
          ping: -> 'pong'
          abc: -> 'xyz'
      }, ->
        new Promise (resolve) ->
          wasAcknoleged = false
          portal = new PortalGun({timeout: 0})
          portal.listen()

          childCall {method: 'abc', params: []}, (res) ->
            if RPCClient.isRPCRequestAcknowledgement res
              wasAcknoleged = true
            else
              portal.close()
              b wasAcknoleged, true
              b RPCClient.isRPCResponse res
              b res.result, 'xyz'
              resolve()

    it 'falls back on error', ->
      withParent {
        methods:
          ping: -> 'pong'
          abc: -> throw new Error 'xxx'
      }, ->
        new Promise (resolve) ->
          wasAcknoleged = false
          portal = new PortalGun({timeout: 0})
          portal.listen()
          portal.on 'abc', 'zzz'

          childCall {method: 'abc', params: []}, (res) ->
            if RPCClient.isRPCRequestAcknowledgement res
              wasAcknoleged = true
            else
              portal.close()
              b wasAcknoleged, true
              b RPCClient.isRPCResponse res
              b res.error.code, -1
              b res.error.message, 'Error'
              resolve()

    it 'registers basic functions', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', -> 'xyz'

      childCall {method: 'abc', params: []}, (res) ->
        if RPCClient.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b RPCClient.isRPCResponse res
          b res.result, 'xyz'
          done()

    it 'registers basic functions with parameters', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', (param) ->
        "hello #{param}"

      childCall {method: 'abc', params: ['world']}, (res) ->
        portal.close()
        if RPCClient.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b RPCClient.isRPCResponse res
          b res.result, 'hello world'
          done()

    it 'registers promise returning functions', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', -> Promise.resolve 'xyz'

      childCall {method: 'abc', params: []}, (res) ->
        if RPCClient.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          portal.close()
          b wasAcknoleged, true
          b RPCClient.isRPCResponse res
          b res.result, 'xyz'
          done()

    it 'supports long-running requests', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', ->
        new Promise (resolve) ->
          setTimeout ->
            resolve 'xyz'
          , 10

      childCall {method: 'abc', params: []}, (res) ->
        if RPCClient.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          portal.close()
          b wasAcknoleged, true
          b RPCClient.isRPCResponse res
          b res.result, 'xyz'
          done()
