# Function::bind polyfill for rewirejs + phantomjs
# coffeelint: disable=missing_fat_arrows
unless Function::bind
  Function::bind = (oThis) ->

    # closest thing possible to the ECMAScript 5
    # internal IsCallable function
    throw new TypeError('Function.prototype.bind - what is trying to be bound
     is not callable')  if typeof this isnt 'function'
    aArgs = Array::slice.call(arguments, 1)
    fToBind = this
    fNOP = -> null

    fBound = ->
      fToBind.apply (if this instanceof fNOP and oThis then this else oThis),
      aArgs.concat(Array::slice.call(arguments))

    fNOP.prototype = this.prototype
    fBound:: = new fNOP()
    fBound
# coffeelint: enable=missing_fat_arrows

_ = require 'lodash'
rewire = require 'rewire'
Promise = require 'bluebird'
should = require('clay-chai').should()

packageConfig = require '../package.json'
portal = rewire '../src/index'

TRUSTED_DOMAINS = ['clay.io', 'staging.wtf']

postRoutes = {}

portal.__set__ 'window.parent.postMessage', (messageString, targetOrigin) ->
  targetOrigin.should.be '*'
  message = JSON.parse messageString
  _.isString(message.id).should.be true
  message._portal.should.be true
  message.jsonrpc.should.be '2.0'

  postRoutes[message.method].should.exist

  if postRoutes[message.method].timeout
    return

  result = postRoutes[message.method].data

  if typeof result is 'function'
    result = result(message)

  e = document.createEvent 'Event'
  e.initEvent 'message', true, true

  e.origin = postRoutes[message.method].origin or
             ('http://' + TRUSTED_DOMAINS[0])
  e.data = JSON.stringify _.defaults(
    {id: message.id, _portal: true}
    result
  )

  window.dispatchEvent e

dispatchEvent = (data) ->
  new Promise (resolve, reject) ->
    e = document.createEvent 'Event'
    e.initEvent 'message', true, true

    e.source =
      postMessage: (messageString, targetOrigin) ->
        targetOrigin.should.be '*'
        message = JSON.parse messageString
        message.id.should.be '1'
        message._portal.should.be true
        message.jsonrpc.should.be '2.0'

        if message.error
          reject message.error
        if message.acknowledge
          return
        else
          resolve message.result

    e.origin = "http://#{TRUSTED_DOMAINS[0]}"
    e.data = JSON.stringify _.defaults(
      {id: '1', _portal: true}
      data
    )

    window.dispatchEvent e

routePost = (method, {origin, data, timeout}) ->
  postRoutes[method] = {origin, data, timeout}

routePost 'ping', data: {result: 'pong'}

describe 'portal-gun', ->
  describe 'up()/down()', ->
    it 'comes up', (done) ->
      listener = portal.__get__ 'window.addEventListener'

      added = ->
        portal.__set__ 'window.addEventListener', listener
        done()

      portal.__set__ 'window.addEventListener', ->
        added()

      portal.up()

    it 'goes down', (done) ->
      listener = portal.__get__ 'window.removeEventListener'

      removed = ->
        portal.__set__ 'window.removeEventListener', listener
        done()

      portal.__set__ 'window.removeEventListener', ->
        removed()

      portal.down()

  describe 'call()', ->
    before ->
      portal.up trusted: TRUSTED_DOMAINS

    it 'posts to parent frame', ->
      routePost 'mirror',
        data:
          result: {test: true}

      portal.call 'mirror'
      .then (user) ->
        user.test.should.be true

    it 'recieves errors', ->
      routePost 'mirror',
        data:
          error: {message: 'abc'}

      portal.call 'mirror'
      .then ->
        throw new Error 'Missing error'
      ,(err) ->
        err.message.should.be 'abc'

    it 'times out', ->
      portal.__with__({'REQUEST_TIMEOUT_MS': 1}) ->
        routePost 'infinite.loop', timeout: true

        portal.call 'infinite.loop'
        .then ->
          throw new Error 'Missing error'
        , (err) ->
          err.message.should.be 'Message Timeout'

          # timeout immediately after first failure
          portal.__with__({'REQUEST_TIMEOUT_MS': 99999}) ->
            portal.call 'infinite.loop'
            .then ->
              throw new Error 'Missing error'
            , (err) ->
              err.message.should.be 'Message Timeout'

    it 'supports callbacks', (done) ->
      routePost 'callme', {
        data: (message) ->
          message.params[0]._portalGunCallback.should.be true

          setTimeout ->
            dispatchEvent {
              callbackId: message.params[0].callbackId
              params: ['back']
            }
          , 10
          return {result: 'noop'}
      }

      portal.call 'callme', (res) ->
        res.should.be 'back'
        done()
      .then (res) ->
        res.should.be 'noop'
      .catch done


    it 'supports callbacks with multiple params', (done) ->
      routePost 'callmemany', {
        data: (message) ->
          message.params[0].should.be 'abc'
          message.params[1]._portalGunCallback.should.be true

          setTimeout ->
            dispatchEvent {
              callbackId: message.params[1].callbackId
              params: ['abc']
            }
          , 10
          return {result: 'noop'}
      }

      portal.call 'callmemany', ['abc', ((res) ->
        res.should.be 'abc'
        done()
      )]
      .then (res) ->
        res.should.be 'noop'
      .catch done

  describe 'domain verification', ->
    it 'Succeeds on valid domains', ->
      portal.up trusted: TRUSTED_DOMAINS, allowSubdomains: false

      domains = [
        "http://#{TRUSTED_DOMAINS[0]}/"
        "https://#{TRUSTED_DOMAINS[0]}/"
        "http://#{TRUSTED_DOMAINS[0]}"
        "https://#{TRUSTED_DOMAINS[0]}"
      ]

      Promise.map domains, (domain) ->
        routePost 'domain.test',
          origin: domain
          data:
            result: {test: true}

        portal.call 'domain.test'
          .then (user) ->
            user.test.should.be true

    it 'Succeeds on valid subdomains', ->
      portal.up trusted: TRUSTED_DOMAINS, allowSubdomains: true

      domains = [
        "http://sub.#{TRUSTED_DOMAINS[0]}/"
        "https://sub.#{TRUSTED_DOMAINS[0]}/"
        "http://sub.#{TRUSTED_DOMAINS[0]}"
        "https://sub.#{TRUSTED_DOMAINS[0]}"

        "http://sub.sub.#{TRUSTED_DOMAINS[0]}/"
        "https://sub.sub.#{TRUSTED_DOMAINS[0]}/"
        "http://sub.sub.#{TRUSTED_DOMAINS[0]}"
        "https://sub.sub.#{TRUSTED_DOMAINS[0]}"
      ]

      Promise.map domains, (domain) ->
        routePost 'domain.test',
          origin: domain
          data:
            result: {test: true}

        portal.call 'domain.test'
        .then (user) ->
          user.test.should.be true

    it 'Errors on invalid domains', ->
      portal.up trusted: TRUSTED_DOMAINS, allowSubdomains: false

      domains = [
        'http://evil.io/'
        'http://sub.evil.io/'
        'http://sub.sub.evil.io/'
        "http://evil.io/http://#{TRUSTED_DOMAINS[0]}/"

        "http://sub.#{TRUSTED_DOMAINS[0]}/"
      ]

      Promise.map domains, (domain, i) ->
        routePost "domain.test.#{i}",
          origin: domain
          data:
            result: {test: true}

        portal.call "domain.test.#{i}"
        .then (res) ->
          throw new Error 'Missing error'
        , (err) ->
          (err instanceof Error).should.be true
          err.message.indexOf('Invalid domain').should.not.be -1

  describe 'requests', ->
    before ->
      portal.up()

    it 'handles ping', ->
      dispatchEvent {method: 'ping'}
      .then (result) ->
        result.should.be 'pong'

  describe 'request handlers', ->
    before ->
      portal.up()

    it 'sends request up', ->
      routePost 'ping',
        data: (message) ->
          result: message.params

      dispatchEvent {method: 'ping', params: [{hello: 'world'}]}
      .then (result) ->
        result.should.be [{hello: 'world'}]

        routePost 'ping',
          data:
            result: 'pong'

    it 'falls back on error', ->
      routePost 'ping',
        data:
          error: {code: -1, message: 'Error'}

      dispatchEvent {method: 'ping'}
      .then (result) ->
        result.should.be 'pong'

        routePost 'ping',
          data:
            result: 'pong'

    describe 'on', ->
      it 'registers basic functions', ->
        portal.on 'abc', ->
          return 'def'

        dispatchEvent {method: 'abc'}
        .then (res) ->
          res.should.be 'def'

      it 'registers basic functions with parameters', ->
        portal.on 'add', (a, b) ->
          return a + b

        dispatchEvent {method: 'add', params: [1, 2]}
        .then (res) ->
          res.should.be 3

      it 'registers promise returning functions', ->
        portal.on 'def', ->
          Promise.resolve 'abc'

        dispatchEvent {method: 'def'}
        .then (res) ->
          res.should.be 'abc'

      it 'supports long-running requests', ->
        portal.on 'long', ->
          return new Promise (resolve) ->
            setTimeout ->
              resolve 'finally!'
            , 90

        dispatchEvent {method: 'long'}
        .then (res) ->
          res.should.be 'finally!'
