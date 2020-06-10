import * as _ from 'lodash-es'

import RPCClient from './rpc_client'

const DEFAULT_HANDSHAKE_TIMEOUT_MS = 10000 // 10 seconds
const SW_CONNECT_TIMEOUT_MS = 5000 // 5s

const selfWindow = (typeof window !== 'undefined' && window !== null) ? window : self

class PortalGun {
  /*
  @param {Object} config
  @param {Number} [config.timeout=3000] - request timeout (ms)
  @param {Function<Boolean>} config.isParentValidFn - restrict parent origin
  */
  constructor (param) {
    this.setParent = this.setParent.bind(this)
    this.setInAppBrowserWindow = this.setInAppBrowserWindow.bind(this)
    this.replyInAppBrowserWindow = this.replyInAppBrowserWindow.bind(this)
    this.onMessageInAppBrowserWindow = this.onMessageInAppBrowserWindow.bind(this)
    this.listen = this.listen.bind(this)
    this.close = this.close.bind(this)
    this.call = this.call.bind(this)
    this.onRequest = this.onRequest.bind(this)
    this.onMessage = this.onMessage.bind(this)
    this.on = this.on.bind(this)
    if (param == null) { param = {} }
    let { timeout, handshakeTimeout, isParentValidFn, useSw } = param
    this.handshakeTimeout = handshakeTimeout
    this.isParentValidFn = isParentValidFn
    if (this.isParentValidFn == null) { this.isParentValidFn = () => true }
    if (timeout == null) { timeout = null }
    if (this.handshakeTimeout == null) { this.handshakeTimeout = DEFAULT_HANDSHAKE_TIMEOUT_MS }
    this.isListening = false
    // window?._portalIsInAppBrowser is set by native app. on iOS it isn't set
    // soon enough, so we rely on userAgent
    const isInAppBrowser = window?._portalIsInAppBrowser ||
                      (navigator.userAgent.indexOf('/InAppBrowser') !== -1)
    this.hasParent = ((typeof window !== 'undefined' && window !== null) && (window.self !== window.top)) || isInAppBrowser
    this.parent = window?.parent

    this.client = new RPCClient({
      timeout,
      postMessage: (msg, origin) => {
        if (isInAppBrowser) {
          let queue = (() => {
            try {
              return JSON.parse(localStorage['portal:queue'])
            } catch (error) {
              return null
            }
          })()
          if (queue == null) { queue = [] }
          queue.push(msg)
          return localStorage['portal:queue'] = JSON.stringify(queue)
        } else {
          return this.parent?.postMessage(msg, origin)
        }
      }
    })

    if (useSw == null) {
      useSw = navigator.serviceWorker && (typeof window !== 'undefined' && window !== null) &&
              (window.location.protocol !== 'http:')
    }

    if (useSw) {
      // only use service workers if current page has one
      this.ready = new Promise((resolve, reject) => {
        const readyTimeout = setTimeout(resolve, SW_CONNECT_TIMEOUT_MS)

        return navigator.serviceWorker.ready
          .catch(function () {
            console.log('caught sw error')
            return null
          }).then(registration => {
            const worker = registration?.active
            if (worker) {
              this.sw = new RPCClient({
                timeout,
                postMessage: (msg, origin) => {
                  const swMessageChannel = new MessageChannel()
                  if (swMessageChannel) {
                    swMessageChannel.port1.onmessage = e => {
                      return this.onMessage(e, { isServiceWorker: true })
                    }
                    return worker.postMessage(
                      msg, [swMessageChannel.port2]
                    )
                  }
                }
              })
            }
            clearTimeout(readyTimeout)
            return resolve()
          })
      })
    } else {
      this.ready = Promise.resolve(true)
    }

    // All parents must respond to 'ping' with @registeredMethods
    this.registeredMethods = {
      ping: () => Object.keys(this.registeredMethods)
    }
    this.parentsRegisteredMethods = []
  }

  setParent (parent) {
    this.parent = parent
    return this.hasParent = true
  }

  setInAppBrowserWindow (iabWindow, callback) {
    // can't use postMessage, so this hacky executeScript works
    this.iabWindow = iabWindow
    const readyEvent = navigator.userAgent.indexOf('iPhone') !== -1
      ? 'loadstop' // for some reason need to wait for this on iOS
      : 'loadstart'
    this.iabWindow.addEventListener(readyEvent, () => {
      this.iabWindow.executeScript({
        code: 'window._portalIsInAppBrowser = true;'
      })
      clearInterval(this.iabInterval)
      return this.iabInterval = setInterval(() => {
        return this.iabWindow.executeScript({
          code: "localStorage.getItem('portal:queue');"
        }, values => {
          try {
            values = JSON.parse(values?.[0])
            if (!_.isEmpty(values)) {
              this.iabWindow.executeScript({
                code: "localStorage.setItem('portal:queue', '[]')"
              })
            }
            return _.map(values, callback)
          } catch (err) {
            return console.log(err, values)
          }
        })
      }
      , 100)
    })
    return this.iabWindow.addEventListener('exit', () => {
      return clearInterval(this.iabInterval)
    })
  }

  replyInAppBrowserWindow (data) {
    const escapedData = data.replace(/'/g, "\'")
    return this.iabWindow.executeScript({
      code: `\
if(window._portalOnMessage) \
window._portalOnMessage('${escapedData}')\
`
    })
  }

  onMessageInAppBrowserWindow (data) {
    return this.onMessage({
      data,
      source: {
        postMessage: data => {
          // needs to be defined in native
          return this.call('browser.reply', { data })
        }
      }
    })
  }

  // Binds global message listener
  // Must be called before .call()
  listen () {
    this.isListening = true
    selfWindow.addEventListener('message', this.onMessage);

    // set via win.executeScript in cordova
    (typeof window !== 'undefined' && window !== null) && (window._portalOnMessage = eStr => {
      return this.onMessage({
        debug: true,
        data: (() => {
          try {
            return JSON.parse(eStr)
          } catch (error) {
            console.log('error parsing', eStr)
            return null
          }
        })()
      })
    })

    this.clientValidation = this.client.call('ping', null, { timeout: this.handshakeTimeout })
      .then(registeredMethods => {
        if (this.hasParent) {
          return this.parentsRegisteredMethods = this.parentsRegisteredMethods.concat(
            registeredMethods
          )
        }
      }).catch(() => null)

    return this.swValidation = this.ready.then(() => {
      return this.sw?.call('ping', null, { timeout: this.handshakeTimeout })
    })
      .then(registeredMethods => {
        return this.parentsRegisteredMethods = this.parentsRegisteredMethods.concat(
          registeredMethods
        )
      })
  }

  close () {
    this.isListening = true
    return selfWindow.removeEventListener('message', this.onMessage)
  }

  /*
  @param {String} method
  @param {...*} params
  @returns Promise
  */
  call (method, ...params) {
    if (!this.isListening) {
      return new Promise((resolve, reject) => reject(new Error('Must call listen() before call()')))
    }

    const localMethod = (method, params) => {
      const fn = this.registeredMethods[method]
      if (!fn) {
        throw new Error('Method not found')
      }
      return fn.apply(null, params)
    }

    // TODO: clean this up
    return this.ready.then(() => {
      if (this.hasParent) {
        let parentError = null
        return this.clientValidation
          .then(() => {
            if (this.parentsRegisteredMethods.indexOf(method) === -1) {
              return localMethod(method, params)
            } else {
              return this.client.call(method, params)
                .then(function (result) {
                  // need to send back methods for all parent frames
                  if (method === 'ping') {
                    const localResult = localMethod(method, params)
                    return (result || []).concat(localResult)
                  } else {
                    return result
                  }
                }).catch(err => {
                  parentError = err
                  if (this.sw) {
                    return this.sw.call(method, params)
                      .then(function (result) {
                        // need to send back methods for all parent frames
                        if (method === 'ping') {
                          const localResult = localMethod(method, params)
                          return (result || []).concat(localResult)
                        } else {
                          return result
                        }
                      }).catch(() => localMethod(method, params))
                  } else {
                    return localMethod(method, params)
                  }
                }).catch(function (err) {
                  if ((err.message === 'Method not found') && (parentError !== null)) {
                    throw parentError
                  } else {
                    throw err
                  }
                })
            }
          })
      } else {
        return new Promise(resolve => {
          if (this.sw) {
            return resolve(
              this.swValidation.then(() => {
                if (this.parentsRegisteredMethods.indexOf(method) === -1) {
                  return localMethod(method, params)
                } else {
                  return this.sw.call(method, params)
                    .then(function (result) {
                    // need to send back methods for all parent frames
                      if (method === 'ping') {
                        const localResult = localMethod(method, params)
                        return (result || []).concat(localResult)
                      } else {
                        return result
                      }
                    }).catch(err => localMethod(method, params))
                }
              })
            )
          } else {
            return resolve(localMethod(method, params))
          }
        })
      }
    })
  }

  onRequest (reply, request) {
    // replace callback params with proxy functions
    const params = []
    for (const param of Array.from((request.params || []))) {
      if (RPCClient.isRPCCallback(param)) {
        (param => params.push((...args) => reply(RPCClient.createRPCCallbackResponse({
          params: args,
          callbackId: param.callbackId
        }))))(param)
      } else {
        params.push(param)
      }
    }

    // acknowledge request, prevent request timeout
    reply(RPCClient.createRPCRequestAcknowledgement({ requestId: request.id }))

    return this.call(request.method, ...Array.from(params))
      .then(result => reply(RPCClient.createRPCResponse({
        requestId: request.id,
        result
      })))
      .catch(err => reply(RPCClient.createRPCResponse({
        requestId: request.id,
        rPCError: RPCClient.createRPCError({
          code: RPCClient.ERROR_CODES.DEFAULT,
          data: err
        })
      })))
  }

  onMessage (e, param) {
    if (param == null) { param = {} }
    const { isServiceWorker } = param
    const reply = function (message) {
      if (typeof window !== 'undefined' && window !== null) {
        return e.source?.postMessage(JSON.stringify(message), '*')
      } else {
        return e.ports[0].postMessage(JSON.stringify(message))
      }
    }

    try { // silent
      const message = typeof e.data === 'string' ? JSON.parse(e.data) : e.data

      if (!RPCClient.isRPCEntity(message)) {
        throw new Error('Non-portal message')
      }

      if (RPCClient.isRPCRequest(message)) {
        return this.onRequest(reply, message)
      } else if (RPCClient.isRPCEntity(message)) {
        let rpc
        if (this.isParentValidFn(e.origin)) {
          rpc = isServiceWorker ? this.sw : this.client
          return rpc.resolve(message)
        } else if (RPCClient.isRPCResponse(message)) {
          rpc = isServiceWorker ? this.sw : this.client
          return rpc.resolve(RPCClient.createRPCResponse({
            requestId: message.id,
            rPCError: RPCClient.createRPCError({
              code: RPCClient.ERROR_CODES.INVALID_ORIGIN
            })
          }))
        } else {
          throw new Error('Invalid origin')
        }
      } else {
        throw new Error('Unknown RPCEntity type')
      }
    } catch (err) {

    }
  }

  /*
  * Register method to be called on child request, or local request fallback
  @param {String} method
  @param {Function} fn
  */
  on (method, fn) {
    return this.registeredMethods[method] = fn
  }
}

export default PortalGun
