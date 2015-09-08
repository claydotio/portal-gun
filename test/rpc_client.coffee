require './polyfill'

b = require 'b-assert'

RPCClient = require '../src/rpc_client'

describe 'rpc-client', ->
  it 'creates RPCRequest', ->
    client = new RPCClient()
    res = client.createRPCRequest({method: 'm', params: ['a', 'b']})
    b res._portal, true
    b _.isString res.id
    b res.method, 'm'
    b res.params, ['a', 'b']

  it 'creates RPCCallback', ->
    client = new RPCClient()
    res = client.createRPCCallback()
    b res._portal, true
    b res._portalGunCallback, true
    b _.isString res.callbackId

  it 'creates RPCCallbackResponse', ->
    client = new RPCClient()
    res = client.createRPCCallbackResponse({params: ['x'], callbackId: 'x'})
    b res, {
      _portal: true
      callbackId: 'x'
      params: ['x']
    }

  it 'creates RPCRequestAcknowledgement', ->
    client = new RPCClient()
    res = client.createRPCRequestAcknowledgement({requestId: 'x'})
    b res, {
      _portal: true
      id: 'x'
      acknowledge: true
    }

  it 'creates RPCError', ->
    client = new RPCClient()
    res = client.createRPCError({code: -1, data: {x: 'y'}})
    b res, {
      _portal: true
      code: -1
      message: 'Error'
      data: {x: 'y'}
    }

  it 'creates RPCResponse', ->
    client = new RPCClient()
    res = client.createRPCResponse({requestId: 'x', result: 'z'})
    b res, {
      _portal: true
      id: 'x'
      result: 'z'
      error: null
    }

  it 'creates RPCResponse with error', ->
    client = new RPCClient()
    error = client.createRPCError({code: -1, data: {x: 'y'}})
    res = client.createRPCResponse({requestId: 'x', rPCError: error})
    b res, {
      _portal: true
      id: 'x'
      error: error
      result: null
    }

  it 'isRPCEntity', ->
    client = new RPCClient()
    b client.isRPCEntity({_portal: true}), true
    b client.isRPCEntity({_portal: false}), false

  it 'isRPCRequest', ->
    client = new RPCClient()
    b client.isRPCRequest({id: 'x', method: 'y'}), true
    b client.isRPCRequest({id: 'x', method: null}), false

  it 'isRPCCallback', ->
    client = new RPCClient()
    b client.isRPCCallback({_portalGunCallback: true}), true
    b client.isRPCCallback({_portalGunCallback: false}), false

  it 'isRPCResponse', ->
    client = new RPCClient()
    b client.isRPCResponse({id: 'x', result: 'x'}), true
    b client.isRPCResponse({id: 'x', error: 'x'}), true
    b client.isRPCResponse({id: 'x'}), false

  it 'isRPCCallbackResponse', ->
    client = new RPCClient()
    b client.isRPCCallbackResponse({callbackId: 'x', params: []}), true
    b client.isRPCCallbackResponse({callbackId: 'x'}), false

  it 'isRPCRequestAcknowledgement', ->
    client = new RPCClient()
    b client.isRPCRequestAcknowledgement({acknowledge: true}), true
    b client.isRPCRequestAcknowledgement({acknowledge: false}), false

  it 'calls remote function', (done) ->
    client = new RPCClient({
      postMessage: (msg) ->
        b client.isRPCRequest(JSON.parse(msg))
        done()
    })
    client.call 'add', [1, 2]

  it 'calls remote function with callback', (done) ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse(msg)
        b client.isRPCRequest(req)
        b client.isRPCCallback req.params[1]
        done()
    })
    client.call 'add', [1, (-> null)]

  it 'times out request', (done) ->
    client = new RPCClient({
      postMessage: -> null
      timeout: 10
    })
    client.call 'add', [1, 2]
    .catch (err) ->
      b err.message, 'Message Timeout'
      done()

  it 'resolves responses', ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse msg
        client.resolve client.createRPCResponse({
          requestId: req.id
          result: 'z'
        })
    })
    client.call 'add', [1, 2]
    .then (z) ->
      b z, 'z'

  it 'resolves acknowlegements', ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse msg
        client.resolve client.createRPCRequestAcknowledgement({
          requestId: req.id
        })
        setTimeout ->
          client.resolve client.createRPCResponse({
            requestId: req.id
            result: 'z'
          })
        , 20
    })
    client.call 'add', [1, 2]
    .then (z) ->
      b z, 'z'

  it 'doesnt time out if acknowledged', (done) ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse msg
        client.resolve client.createRPCRequestAcknowledgement({
          requestId: req.id
        })
      timeout: 10
    })
    client.call 'add', [1, 2]
    .then -> done new Error 'should not complete'
    .catch done
    setTimeout ->
      done()
    , 20

  it 'resolves callback responses', (done) ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse msg
        rPCCallback = req.params[1]
        client.resolve client.createRPCCallbackResponse({
          params: ['x']
          callbackId: rPCCallback.callbackId
        })
    })
    fn = (x) ->
      b x, 'x'
      done()
    client.call 'add', [1, fn]
