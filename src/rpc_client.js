/*
 * Child {RPCRequest} -> Parent
 *   Parent {RPCRequestAcknowledgement} -> Child
 *   Parent {RPCResponse} -> Child
 *
 * Child {RPCRequest:{params:[RPCCallback]}} -> Parent
 *   Parent {RPCRequestAcknowledgement} -> Child
 *   Parent {RPCResponse} -> Child
 *   Parent {RPCCallbackResponse} -> Child
 *   Parent {RPCCallbackResponse} -> Child
 *
 * Parent {RPCError} -> Child
 *
 *
 * _portal is added to denote a portal-gun message
 * RPCRequestAcknowledgement is to ensure the responder recieved the request
 * RPCCallbackResponse is added to support callbacks for methods
 *
 * params, if containing a callback function, will have that method replaced
 * with RPCCallback which should be used to emit callback responses
 */

import uuid from 'uuid'
let RPCClient

const ERROR_CODES = {
  METHOD_NOT_FOUND: -32601,
  INVALID_ORIGIN: 100,
  DEFAULT: -1
}

const ERROR_MESSAGES = {}
ERROR_MESSAGES[ERROR_CODES.METHOD_NOT_FOUND] = 'Method not found'
ERROR_MESSAGES[ERROR_CODES.INVALID_ORIGIN] = 'Invalid origin'
ERROR_MESSAGES[ERROR_CODES.DEFAULT] = 'Error'

const DEFAULT_REQUEST_TIMEOUT_MS = 3000

const deferredFactory = function () {
  let resolve = null
  let reject = null
  const promise = new Promise(function (_resolve, _reject) {
    resolve = _resolve
    return reject = _reject
  })
  promise.resolve = resolve
  promise.reject = reject

  return promise
}

export default RPCClient = (function () {
  RPCClient = class RPCClient {
    static initClass () {
      this.ERROR_CODES = ERROR_CODES
      this.ERROR_MESSAGES = ERROR_MESSAGES
    }

    constructor (param) {
      this.call = this.call.bind(this)
      this.resolve = this.resolve.bind(this)
      this.resolveRPCResponse = this.resolveRPCResponse.bind(this)
      this.resolveRPCRequestAcknowledgement = this.resolveRPCRequestAcknowledgement.bind(this)
      this.resolveRPCCallbackResponse = this.resolveRPCCallbackResponse.bind(this)
      if (param == null) { param = {} }
      const { postMessage, timeout } = param
      this.postMessage = postMessage
      this.timeout = timeout
      if (this.timeout == null) { this.timeout = DEFAULT_REQUEST_TIMEOUT_MS }
      this.pendingRequests = {}
      this.callbackFunctions = {}
    }

    /*
    @typedef {Object} RPCRequest
    @property {Boolean} _portal - Must be true
    @property {String} id
    @property {String} method
    @property {Array<*>} params

    @param {Object} props
    @param {String} props.method
    @param {Array<*>} [props.params] - Functions are not allowed
    @returns RPCRequest
    */
    static createRPCRequest ({ method, params }) {
      if (params == null) {
        throw new Error('Must provide params')
      }

      for (const param of Array.from(params)) {
        if (typeof param === 'function') {
          throw new Error('Functions are not allowed. Use RPCCallback instead.')
        }
      }

      return { _portal: true, id: uuid.v4(), method, params }
    }

    /*
    @typedef {Object} RPCCallback
    @property {Boolean} _portal - Must be true
    @property {String} callbackId
    @property {Boolean} _portalGunCallback - Must be true

    @returns RPCCallback
    */
    static createRPCCallback () {
      return { _portal: true, _portalGunCallback: true, callbackId: uuid.v4() }
    }

    /*
    @typedef {Object} RPCCallbackResponse
    @property {Boolean} _portal - Must be true
    @property {String} callbackId
    @property {Array<*>} params

    @param {Object} props
    @param {Array<*>} props.params
    @param {String} props.callbackId
    @returns RPCCallbackResponse
    */
    static createRPCCallbackResponse ({ params, callbackId }) {
      return { _portal: true, callbackId, params }
    }

    /*
    @typedef {Object} RPCRequestAcknowledgement
    @property {Boolean} _portal - Must be true
    @property {String} id
    @property {Boolean} acknowledge - must be true

    @param {Object} props
    @param {String} props.responseId
    @returns RPCRequestAcknowledgement
    */
    static createRPCRequestAcknowledgement ({ requestId }) {
      return { _portal: true, id: requestId, acknowledge: true }
    }

    /*
    @typedef {Object} RPCResponse
    @property {Boolean} _portal - Must be true
    @property {String} id
    @property {*} result
    @property {RPCError} error

    @param {Object} props
    @param {String} props.requestId
    @param {*} [props.result]
    @param {RPCError|Null} [props.error]
    @returns RPCResponse
    */
    static createRPCResponse ({ requestId, result, rPCError }) {
      if (result == null) { result = null }
      if (rPCError == null) { rPCError = null }
      return { _portal: true, id: requestId, result, error: rPCError }
    }

    /*
    @typedef {Object} RPCError
    @property {Boolean} _portal - Must be true
    @property {Integer} code
    @property {String} message
    @property {Object} data - optional

    @param {Object} props
    @param {Errpr} [props.error]
    @returns RPCError
    */
    static createRPCError ({ code, data }) {
      if (data == null) { data = null }
      const message = ERROR_MESSAGES[code]
      return { _portal: true, code, message, data }
    }

    static isRPCEntity (entity) { return entity?._portal }
    static isRPCRequest (request) {
      return (request?.id != null) && (request.method != null)
    }

    static isRPCCallback (callback) { return callback?._portalGunCallback }
    static isRPCResponse (response) {
      return response?.id && (
        (response.result !== undefined) || (response.error !== undefined)
      )
    }

    static isRPCCallbackResponse (response) {
      return (response?.callbackId != null) && (response.params != null)
    }

    static isRPCRequestAcknowledgement (ack) { return ack?.acknowledge === true }

    /*
    @param {String} method
    @param {Array<*>} [params]
    @returns {Promise}
    */
    call (method, reqParams, param1) {
      if (param1 == null) { param1 = {} }
      let { timeout } = param1
      if (!reqParams) { reqParams = [] }
      if (timeout == null) {
        ({
          timeout
        } = this)
      }
      const deferred = deferredFactory()
      const params = []

      // replace callback params
      for (const param of Array.from(reqParams)) {
        if (typeof param === 'function') {
          const callback = RPCClient.createRPCCallback(param)
          this.callbackFunctions[callback.callbackId] = param
          params.push(callback)
        } else {
          params.push(param)
        }
      }

      const request = RPCClient.createRPCRequest({ method, params })

      this.pendingRequests[request.id] = {
        reject: deferred.reject,
        resolve: deferred.resolve,
        isAcknowledged: false
      }

      try {
        this.postMessage(JSON.stringify(request), '*')
      } catch (err) {
        deferred.reject(err)
        return deferred
      }

      setTimeout(() => {
        if (!this.pendingRequests[request.id].isAcknowledged) {
          return deferred.reject(new Error('Message Timeout'))
        }
      }
      , timeout)

      return deferred
    }

    /*
    @param {RPCResponse|RPCRequestAcknowledgement|RPCCallbackResponse} response
    */
    resolve (response) {
      switch (false) {
        case !RPCClient.isRPCRequestAcknowledgement(response):
          return this.resolveRPCRequestAcknowledgement(response)
        case !RPCClient.isRPCResponse(response):
          return this.resolveRPCResponse(response)
        case !RPCClient.isRPCCallbackResponse(response):
          return this.resolveRPCCallbackResponse(response)
        default:
          throw new Error('Unknown response type')
      }
    }

    /*
    @param {RPCResponse} rPCResponse
    */
    resolveRPCResponse (rPCResponse) {
      const request = this.pendingRequests[rPCResponse.id]
      if (request == null) {
        throw new Error('Request not found')
      }

      request.isAcknowledged = true

      const { result, error } = rPCResponse
      if (error != null) {
        request.reject(error.data || new Error(error.message))
      } else if (result != null) {
        request.resolve(result)
      } else {
        request.resolve(null)
      }
      return null
    }

    /*
    @param {RPCRequestAcknowledgement} rPCRequestAcknowledgement
    */
    resolveRPCRequestAcknowledgement (rPCRequestAcknowledgement) {
      const request = this.pendingRequests[rPCRequestAcknowledgement.id]
      if (request == null) {
        throw new Error('Request not found')
      }

      request.isAcknowledged = true
      return null
    }

    /*
    @param {RPCCallbackResponse} rPCCallbackResponse
    */
    resolveRPCCallbackResponse (rPCCallbackResponse) {
      const callbackFn = this.callbackFunctions[rPCCallbackResponse.callbackId]
      if (callbackFn == null) {
        throw new Error('Callback not found')
      }

      callbackFn.apply(null, rPCCallbackResponse.params)
      return null
    }
  }
  RPCClient.initClass()
  return RPCClient
})()
