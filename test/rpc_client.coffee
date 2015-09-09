require './polyfill'

b = require 'b-assert'

RPCClient = require '../src/rpc_client'

describe 'rpc-client', ->
  it 'has error codes', ->
    b RPCClient.ERROR_CODES.METHOD_NOT_FOUND, -32601
    b RPCClient.ERROR_CODES.DEFAULT, -1

  it 'has error messages', ->
    notFound = RPCClient.ERROR_CODES.METHOD_NOT_FOUND
    def = RPCClient.ERROR_CODES.DEFAULT

    b RPCClient.ERROR_MESSAGES[notFound], 'Method not found'
    b RPCClient.ERROR_MESSAGES[def], 'Error'

  it 'creates RPCRequest', ->
    res = RPCClient.createRPCRequest({method: 'm', params: ['a', 'b']})
    b res._portal, true
    b _.isString res.id
    b res.method, 'm'
    b res.params, ['a', 'b']

  it 'creates RPCCallback', ->
    res = RPCClient.createRPCCallback()
    b res._portal, true
    b res._portalGunCallback, true
    b _.isString res.callbackId

  it 'creates RPCCallbackResponse', ->
    res = RPCClient.createRPCCallbackResponse({params: ['x'], callbackId: 'x'})
    b res, {
      _portal: true
      callbackId: 'x'
      params: ['x']
    }

  it 'creates RPCRequestAcknowledgement', ->
    res = RPCClient.createRPCRequestAcknowledgement({requestId: 'x'})
    b res, {
      _portal: true
      id: 'x'
      acknowledge: true
    }

  it 'creates RPCError', ->
    res = RPCClient.createRPCError({code: -1, data: {x: 'y'}})
    b res, {
      _portal: true
      code: -1
      message: 'Error'
      data: {x: 'y'}
    }

  it 'creates RPCResponse', ->
    res = RPCClient.createRPCResponse({requestId: 'x', result: 'z'})
    b res, {
      _portal: true
      id: 'x'
      result: 'z'
      error: null
    }

  it 'creates RPCResponse with error', ->
    error = RPCClient.createRPCError({code: -1, data: {x: 'y'}})
    res = RPCClient.createRPCResponse({requestId: 'x', rPCError: error})
    b res, {
      _portal: true
      id: 'x'
      error: error
      result: null
    }

  it 'isRPCEntity', ->
    b RPCClient.isRPCEntity({_portal: true}), true
    b RPCClient.isRPCEntity({_portal: false}), false

  it 'isRPCRequest', ->
    b RPCClient.isRPCRequest({id: 'x', method: 'y'}), true
    b RPCClient.isRPCRequest({id: 'x', method: null}), false

  it 'isRPCCallback', ->
    b RPCClient.isRPCCallback({_portalGunCallback: true}), true
    b RPCClient.isRPCCallback({_portalGunCallback: false}), false

  it 'isRPCResponse', ->
    b RPCClient.isRPCResponse({id: 'x', result: 'x'}), true
    b RPCClient.isRPCResponse({id: 'x', error: 'x'}), true
    b RPCClient.isRPCResponse({id: 'x'}), false

  it 'isRPCCallbackResponse', ->
    b RPCClient.isRPCCallbackResponse({callbackId: 'x', params: []}), true
    b RPCClient.isRPCCallbackResponse({callbackId: 'x'}), false

  it 'isRPCRequestAcknowledgement', ->
    b RPCClient.isRPCRequestAcknowledgement({acknowledge: true}), true
    b RPCClient.isRPCRequestAcknowledgement({acknowledge: false}), false

  it 'calls remote function', (done) ->
    client = new RPCClient({
      postMessage: (msg) ->
        b RPCClient.isRPCRequest(JSON.parse(msg))
        done()
    })
    client.call 'add', [1, 2]

  it 'calls remote function with callback', (done) ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse(msg)
        b RPCClient.isRPCRequest(req)
        b RPCClient.isRPCCallback req.params[1]
        done()
    })
    client.call 'add', [1, (-> null)]

  it 'times out all requests', (done) ->
    client = new RPCClient({
      postMessage: -> null
      timeout: 10
    })
    client.call 'add', [1, 2]
    .catch (err) ->
      b err.message, 'Message Timeout'
      done()

  it 'times out single request', (done) ->
    client = new RPCClient({
      postMessage: -> null
      timeout: 10000
    })
    client.call 'add', [1, 2], {timeout: 0}
    .catch (err) ->
      b err.message, 'Message Timeout'
      done()

  it 'resolves responses', ->
    client = new RPCClient({
      postMessage: (msg) ->
        req = JSON.parse msg
        client.resolve RPCClient.createRPCResponse({
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
        client.resolve RPCClient.createRPCRequestAcknowledgement({
          requestId: req.id
        })
        setTimeout ->
          client.resolve RPCClient.createRPCResponse({
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
        client.resolve RPCClient.createRPCRequestAcknowledgement({
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
        client.resolve RPCClient.createRPCCallbackResponse({
          params: ['x']
          callbackId: rPCCallback.callbackId
        })
    })
    fn = (x) ->
      b x, 'x'
      done()
    client.call 'add', [1, fn]
