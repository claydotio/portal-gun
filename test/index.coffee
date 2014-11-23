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

TRUSTED_DOMAIN = 'clay.io'

postRoutes = {}

portal.__set__ 'window.parent.postMessage', (messageString, targetOrigin) ->
  targetOrigin.should.be '*'
  message = JSON.parse messageString
  _.isNumber(message.id).should.be true
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

  e.origin = postRoutes[message.method].origin or ('http://' + TRUSTED_DOMAIN)
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
        message.id.should.be 1
        message._portal.should.be true
        message.jsonrpc.should.be '2.0'

        if message.error
          reject message.error
        else
          resolve message.result

    e.origin = 'http://anysite.com'
    e.data = JSON.stringify _.defaults(
      {id: 1, _portal: true}
      data
    )

    window.dispatchEvent e

routePost = (method, {origin, data, timeout}) ->
  postRoutes[method] = {origin, data, timeout}

routePost 'ping', data: {result: 'pong'}

# TODO callbacks
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

  describe 'get()', ->
    before ->
      portal.up trusted: TRUSTED_DOMAIN

    it 'posts to parent frame', ->
      routePost 'mirror',
        data:
          result: {test: true}

      portal.get 'mirror'
      .then (user) ->
        user.test.should.be true

    it 'recieves errors', ->
      routePost 'mirror',
        data:
          error: {message: 'abc'}

      portal.get 'mirror'
      .then ->
        throw new Error 'Missing error'
      ,(err) ->
        err.message.should.be 'abc'

    it 'times out', ->
      portal.__set__ 'ONE_SECOND_MS', 10
      routePost 'infinite.loop', timeout: true

      portal.get 'infinite.loop'
      .then ->
        throw new Error 'Missing error'
      ,(err) ->
        portal.__set__ 'ONE_SECOND_MS', 1000
        err.message.should.be 'Message Timeout'

  describe 'domain verification', ->
    it 'Succeeds on valid domains', ->
      portal.up trusted: TRUSTED_DOMAIN, subdomains: false

      domains = [
        "http://#{TRUSTED_DOMAIN}/"
        "https://#{TRUSTED_DOMAIN}/"
        "http://#{TRUSTED_DOMAIN}"
        "https://#{TRUSTED_DOMAIN}"
      ]

      Promise.map domains, (domain) ->
        routePost 'domain.test',
          origin: domain
          data:
            result: {test: true}

        portal.get 'domain.test'
          .then (user) ->
            user.test.should.be true

    it 'Succeeds on valid subdomains', ->
      portal.up trusted: TRUSTED_DOMAIN, subdomains: true

      domains = [
        "http://sub.#{TRUSTED_DOMAIN}/"
        "https://sub.#{TRUSTED_DOMAIN}/"
        "http://sub.#{TRUSTED_DOMAIN}"
        "https://sub.#{TRUSTED_DOMAIN}"

        "http://sub.sub.#{TRUSTED_DOMAIN}/"
        "https://sub.sub.#{TRUSTED_DOMAIN}/"
        "http://sub.sub.#{TRUSTED_DOMAIN}"
        "https://sub.sub.#{TRUSTED_DOMAIN}"
      ]

      Promise.map domains, (domain) ->
        routePost 'domain.test',
          origin: domain
          data:
            result: {test: true}

        portal.get 'domain.test'
        .then (user) ->
          user.test.should.be true

    it 'Errors on invalid domains', ->
      portal.up trusted: TRUSTED_DOMAIN, subdomains: false

      domains = [
        'http://evil.io/'
        'http://sub.evil.io/'
        'http://sub.sub.evil.io/'
        "http://evil.io/http://#{TRUSTED_DOMAIN}/"

        "http://sub.#{TRUSTED_DOMAIN}/"
      ]

      Promise.map domains, (domain, i) ->
        routePost "domain.test.#{i}",
          origin: domain
          data:
            result: {test: true}

        portal.get "domain.test.#{i}"
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

    describe 'register', ->
      it 'registers basic functions', ->
        portal.register 'abc', ->
          return 'def'

        dispatchEvent {method: 'abc'}
        .then (res) ->
          res.should.be 'def'

      it 'registers basic functions with parameters', ->
        portal.register 'add', (a, b) ->
          return a + b

        dispatchEvent {method: 'add', params: [1, 2]}
        .then (res) ->
          res.should.be 3


      it 'registers promise returning functions', ->
        portal.register 'def', ->
          Promise.resolve 'abc'

        dispatchEvent {method: 'def'}
        .then (res) ->
          res.should.be 'abc'
