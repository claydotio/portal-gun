require './polyfill'

_ = require 'lodash'
rewire = require 'rewire'
Promise = require 'bluebird'
# FIXME
should = require('clay-chai').should()
b = require 'b-assert'

PortalGun = require '../src/index'
RPCClient = require '../src/rpc_client'

client = new RPCClient()

withParent = ({methods, origin}, fn) ->
  oldPost = window.parent?.postMessage
  window.parent?.postMessage = (msg) ->
    req = JSON.parse msg
    b client.isRPCRequest req
    reply = (message) ->
      e = document.createEvent 'Event'
      e.initEvent 'message', true, true
      e.origin = origin
      e.data = JSON.stringify message
      window.dispatchEvent e

    # replace callback params with proxy functions
    params = []
    for param in req.params
      if client.isRPCCallback param
        do (param) ->
          params.push (args...) ->
            reply client.createRPCCallbackResponse {
              params: args
              callbackId: param.callbackId
            }
      else
        params.push param

    new Promise (resolve) ->
      resolve methods[req.method](params...)
    .then (result) ->
      reply client.createRPCResponse {
        requestId: req.id
        result: result
      }
    .catch (err) ->
      reply client.createRPCResponse {
        requestId: req.id
        rPCError: client.createRPCError {code: -1}
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
  e.data = JSON.stringify client.createRPCRequest request
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

  describe 'call()', ->
    it 'requires listening before calling', (done) ->
      portal = new PortalGun()
      portal.call 'ping'
      .catch (err) ->
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
          b pong, 'pong'

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
            b res, 'xxx'
            resolve()

    it 'calls method with callback with multiple params', ->
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
          b xxx, 'xxx'
          b yyy, 'yyy'
          done()

    it 'succeeds on valid domains', ->
      domains = [
        'http://x.com/'
        'https://x.com/'
        'http://x.com'
        'https://x.com'
      ]
      Promise.map domains, (domain) ->
        withParent {
          origin: domain
          methods:
            ping: -> 'pong'
        }, ->
          portal = new PortalGun({
            trusted: ['x.com']
          })
          portal.listen()
          portal.call 'ping'
          .then (res) ->
            b res, 'pong'

    it 'succeeds on valid subdomains', ->
      domains = [
        'http://sub.x.com/'
        'https://sub.x.com/'
        'http://sub.x.com'
        'https://sub.x.com'

        'http://sub.sub.x.com/'
        'https://sub.sub.x.com/'
        'http://sub.sub.x.com'
        'https://sub.sub.x.com'
      ]

      Promise.map domains, (domain) ->
        withParent {
          origin: domain
          methods:
            ping: -> 'pong'
        }, ->
          portal = new PortalGun({
            trusted: ['x.com']
            allowSubdomains: true
          })
          portal.listen()
          portal.call 'ping'
          .then (res) ->
            b res, 'pong'

    it 'fails on invalid domains', ->
      domains = [
        'http://evil.io/'
        'http://evil.io/http://x.com/'
      ]

      Promise.map domains, (domain) ->
        withParent {
          origin: domain
          methods:
            ping: -> 'pong'
            abc: -> 'xyz'
        }, ->
          portal = new PortalGun({
            trusted: ['x.com']
          })
          portal.listen()
          portal.call 'abc'
          .then ->
            throw new Error 'Missing Error'
          , (err) ->
            b err.message, 'Invalid origin'


    it 'fails on invalid subdomains', ->
      domains = [
        'http://sub.evil.io/'
        'http://sub.sub.evil.io/'

        'http://sub.x.com/'
      ]

      Promise.map domains, (domain) ->
        withParent {
          origin: domain
          methods:
            ping: -> 'pong'
            abc: -> 'xyz'
        }, ->
          portal = new PortalGun({
            trusted: ['x.com']
            allowSubdomains: false
          })
          portal.listen()
          portal.call 'abc'
          .then ->
            throw new Error 'Missing Error'
          , (err) ->
            b err.message, 'Invalid origin'


  describe 'on()', ->
    it 'responds to ping', (done) ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()

      childCall {method: 'ping', params: []}, (res) ->
        if client.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b client.isRPCResponse res
          b res.result, 'pong'
          done()

    it 'acknowledges immediately', (done) ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'long', ->
        new Promise -> null

      childCall {method: 'long', params: []}, (res) ->
        if client.isRPCRequestAcknowledgement res
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
            if client.isRPCRequestAcknowledgement res
              wasAcknoleged = true
            else
              b wasAcknoleged, true
              b client.isRPCResponse res
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
            if client.isRPCRequestAcknowledgement res
              wasAcknoleged = true
            else
              b wasAcknoleged, true
              b client.isRPCResponse res
              b res.error.code, -1
              b res.error.message, 'Error'
              resolve()

    it 'registers basic functions', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', -> 'xyz'

      childCall {method: 'abc', params: []}, (res) ->
        if client.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b client.isRPCResponse res
          b res.result, 'xyz'
          done()

    it 'registers basic functions with parameters', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', (param) ->
        "hello #{param}"

      childCall {method: 'abc', params: ['world']}, (res) ->
        if client.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b client.isRPCResponse res
          b res.result, 'hello world'
          done()

    it 'registers promise returning functions', ->
      wasAcknoleged = false
      portal = new PortalGun({timeout: 0})
      portal.listen()
      portal.on 'abc', -> Promise.resolve 'xyz'

      childCall {method: 'abc', params: []}, (res) ->
        if client.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b client.isRPCResponse res
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
        if client.isRPCRequestAcknowledgement res
          wasAcknoleged = true
        else
          b wasAcknoleged, true
          b client.isRPCResponse res
          b res.result, 'xyz'
          done()
