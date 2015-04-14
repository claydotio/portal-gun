module.exports =
/******/ (function(modules) { // webpackBootstrap
/******/ 	// The module cache
/******/ 	var installedModules = {};
/******/
/******/ 	// The require function
/******/ 	function __webpack_require__(moduleId) {
/******/
/******/ 		// Check if module is in cache
/******/ 		if(installedModules[moduleId])
/******/ 			return installedModules[moduleId].exports;
/******/
/******/ 		// Create a new module (and put it into the cache)
/******/ 		var module = installedModules[moduleId] = {
/******/ 			exports: {},
/******/ 			id: moduleId,
/******/ 			loaded: false
/******/ 		};
/******/
/******/ 		// Execute the module function
/******/ 		modules[moduleId].call(module.exports, module, module.exports, __webpack_require__);
/******/
/******/ 		// Flag the module as loaded
/******/ 		module.loaded = true;
/******/
/******/ 		// Return the exports of the module
/******/ 		return module.exports;
/******/ 	}
/******/
/******/
/******/ 	// expose the modules object (__webpack_modules__)
/******/ 	__webpack_require__.m = modules;
/******/
/******/ 	// expose the module cache
/******/ 	__webpack_require__.c = installedModules;
/******/
/******/ 	// __webpack_public_path__
/******/ 	__webpack_require__.p = "";
/******/
/******/ 	// Load entry module and return exports
/******/ 	return __webpack_require__(0);
/******/ })
/************************************************************************/
/******/ ([
/* 0 */
/***/ function(module, exports, __webpack_require__) {

	var IS_FRAMED, PortalGun, Poster, Promise, REQUEST_TIMEOUT_MS, deferredFactory, isValidOrigin, portal,
	  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
	  __slice = [].slice;

	Promise = window.Promise || __webpack_require__(1);

	IS_FRAMED = window.self !== window.top;

	REQUEST_TIMEOUT_MS = 1000;

	deferredFactory = function() {
	  var promise, reject, resolve;
	  resolve = null;
	  reject = null;
	  promise = new Promise(function(_resolve, _reject) {
	    resolve = _resolve;
	    return reject = _reject;
	  });
	  promise.resolve = resolve;
	  promise.reject = reject;
	  return promise;
	};

	isValidOrigin = function(origin, trusted, allowSubdomains) {
	  var regex, trust, _i, _len;
	  if (trusted == null) {
	    return true;
	  }
	  for (_i = 0, _len = trusted.length; _i < _len; _i++) {
	    trust = trusted[_i];
	    regex = allowSubdomains ? new RegExp('^https?://(\\w+\\.)?(\\w+\\.)?' + ("" + (trust.replace(/\./g, '\\.')) + "/?$")) : new RegExp('^https?://' + ("" + (trust.replace(/\./g, '\\.')) + "/?$"));
	    if (regex.test(origin)) {
	      return true;
	    }
	  }
	  return false;
	};


	/*
	 * Messages follow the json-rpc 2.0 spec: http://www.jsonrpc.org/specification
	 * _portal is added to denote a portal-gun message
	 * RPCAcknowledgeRequest is added to ensure the responder recieved the request
	 * RPCCallbackResponse is added to support callbacks for methods


	 * params, if containing a callback function, will have that method replaced
	 * with: {_portalGunCallback: true, callbackId: {Number}}
	 * which should be used to emit callback responses

	@typedef {Object} RPCRequest
	@property {Integer} [id] - Without an `id` this is a notification
	@property {String} method
	@property {Array<*>} params
	@property {Boolean} _portal - Must be true
	@property {String} jsonrpc - Must be '2.0'


	@typedef {Object} RPCAcknowledgeRequest
	@property {Integer} id
	@property {Boolean} acknowledge - pre-result response to notify requester
	@property {Boolean} _portal - Must be true
	@property {String} jsonrpc - Must be '2.0'


	@typedef {Object} RPCResponse
	@property {Integer} [id]
	@property {*} result
	@property {RPCError} error


	@typedef {Object} RPCCallbackResponse
	@property {Integer} callbackId
	@property {Array} params


	@typedef {Object} RPCError
	@property {Integer} code
	@property {String} message
	 */

	Poster = (function() {
	  function Poster() {
	    this.resolveMessage = __bind(this.resolveMessage, this);
	    this.postMessage = __bind(this.postMessage, this);
	    this.lastMessageId = 0;
	    this.lastCallbackId = 0;
	    this.pendingMessages = {};
	    this.callbacks = {};
	    this.isParentDead = false;
	  }


	  /*
	  @param {String} method
	  @param {Array} [params]
	  @returns {Promise}
	   */

	  Poster.prototype.postMessage = function(method, reqParams) {
	    var deferred, err, id, message, param, params, _i, _len;
	    if (reqParams == null) {
	      reqParams = [];
	    }
	    deferred = deferredFactory();
	    params = [];
	    for (_i = 0, _len = reqParams.length; _i < _len; _i++) {
	      param = reqParams[_i];
	      if (typeof param === 'function') {
	        this.lastCallbackId += 1;
	        id = this.lastCallbackId;
	        this.callbacks[id] = param;
	        params.push({
	          _portalGunCallback: true,
	          callbackId: id
	        });
	      } else {
	        params.push(param);
	      }
	    }
	    message = {
	      method: method,
	      params: params
	    };
	    try {
	      this.lastMessageId += 1;
	      message.id = "" + this.lastMessageId;
	      message._portal = true;
	      message.jsonrpc = '2.0';
	      this.pendingMessages[message.id] = {
	        reject: deferred.reject,
	        resolve: deferred.resolve,
	        acknowledged: false
	      };
	      window.parent.postMessage(JSON.stringify(message), '*');
	    } catch (_error) {
	      err = _error;
	      deferred.reject(err);
	    }
	    window.setTimeout((function(_this) {
	      return function() {
	        if (!_this.pendingMessages[message.id].acknowledged) {
	          _this.isParentDead = true;
	          return deferred.reject(new Error('Message Timeout'));
	        }
	      };
	    })(this), REQUEST_TIMEOUT_MS);
	    if (this.isParentDead) {
	      deferred.reject(new Error('Message Timeout'));
	    }
	    return deferred;
	  };


	  /*
	  @param {RPCResponse|RPCCallbackResponse|RPCError}
	   */

	  Poster.prototype.resolveMessage = function(message) {
	    if (message.callbackId) {
	      if (!this.callbacks[message.callbackId]) {
	        return Promise.reject(new Error('Method not found'));
	      }
	      return this.callbacks[message.callbackId].apply(null, message.params);
	    } else {
	      if (!this.pendingMessages[message.id]) {
	        return Promise.reject(new Error('Method not found'));
	      } else {
	        this.pendingMessages[message.id].acknowledged = true;
	        if (message.acknowledge) {
	          return Promise.resolve(null);
	        } else if (message.error) {
	          return this.pendingMessages[message.id].reject(new Error(message.error.message));
	        } else {
	          return this.pendingMessages[message.id].resolve(message.result || null);
	        }
	      }
	    }
	  };

	  return Poster;

	})();

	PortalGun = (function() {
	  function PortalGun() {
	    this.on = __bind(this.on, this);
	    this.onMessage = __bind(this.onMessage, this);
	    this.validateParent = __bind(this.validateParent, this);
	    this.call = __bind(this.call, this);
	    this.down = __bind(this.down, this);
	    this.up = __bind(this.up, this);
	    this.config = {
	      trusted: null,
	      allowSubdomains: false
	    };
	    this.poster = new Poster();
	    this.registeredMethods = {
	      ping: function() {
	        return 'pong';
	      }
	    };
	  }


	  /*
	   * Bind global message event listener
	  
	  @param {Object} config
	  @param {Array<String>} config.trusted - trusted domains e.g.['clay.io']
	  @param {Boolean} config.allowSubdomains - trust subdomains of trusted domain
	   */

	  PortalGun.prototype.up = function(_arg) {
	    var allowSubdomains, trusted, _ref;
	    _ref = _arg != null ? _arg : {}, trusted = _ref.trusted, allowSubdomains = _ref.allowSubdomains;
	    if (trusted == null) {
	      trusted = null;
	    }
	    if (allowSubdomains == null) {
	      allowSubdomains = false;
	    }
	    this.config.trusted = trusted;
	    this.config.allowSubdomains = allowSubdomains;
	    return window.addEventListener('message', this.onMessage);
	  };

	  PortalGun.prototype.down = function() {
	    return window.removeEventListener('message', this.onMessage);
	  };


	  /*
	  @param {String} method
	  @param {*} params - Arrays will be deconstructed as multiple args
	   */

	  PortalGun.prototype.call = function(method, params) {
	    var frameError, localMethod;
	    if (params == null) {
	      params = [];
	    }
	    if (Object.prototype.toString.call(params) !== '[object Array]') {
	      params = [params];
	    }
	    localMethod = (function(_this) {
	      return function(method, params) {
	        var fn;
	        fn = _this.registeredMethods[method];
	        if (!fn) {
	          throw new Error('Method not found');
	        }
	        return fn.apply(null, params);
	      };
	    })(this);
	    if (IS_FRAMED) {
	      frameError = null;
	      return this.validateParent().then((function(_this) {
	        return function() {
	          return _this.poster.postMessage(method, params);
	        };
	      })(this))["catch"](function(err) {
	        frameError = err;
	        return localMethod(method, params);
	      })["catch"](function(err) {
	        if (err.message === 'Method not found' && frameError !== null) {
	          throw frameError;
	        } else {
	          throw err;
	        }
	      });
	    } else {
	      return new Promise(function(resolve) {
	        return resolve(localMethod(method, params));
	      });
	    }
	  };

	  PortalGun.prototype.validateParent = function() {
	    return this.poster.postMessage('ping');
	  };

	  PortalGun.prototype.onMessage = function(e) {
	    var err, id, isRequest, message, method, param, params, reqParams, _i, _len;
	    try {
	      message = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
	      if (!message._portal) {
	        throw new Error('Non-portal message');
	      }
	      isRequest = Boolean(message.method);
	      if (isRequest) {
	        params = [];
	        id = message.id, method = message.method;
	        reqParams = message.params || [];
	        for (_i = 0, _len = reqParams.length; _i < _len; _i++) {
	          param = reqParams[_i];
	          if (param != null ? param._portalGunCallback : void 0) {
	            params.push(function() {
	              var params;
	              params = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
	              return e.source.postMessage(JSON.stringify({
	                _portal: true,
	                jsonrpc: '2.0',
	                callbackId: param.callbackId,
	                params: params
	              }), '*');
	            });
	          } else {
	            params.push(param);
	          }
	        }
	        e.source.postMessage(JSON.stringify({
	          _portal: true,
	          jsonrpc: '2.0',
	          id: id,
	          acknowledge: true
	        }), '*');
	        return this.call(method, params).then(function(result) {
	          return e.source.postMessage(JSON.stringify({
	            _portal: true,
	            jsonrpc: '2.0',
	            id: id,
	            result: result
	          }), '*');
	        })["catch"](function(err) {
	          var code;
	          code = (function() {
	            switch (err.message) {
	              case 'Method not found':
	                return -32601;
	              default:
	                return -1;
	            }
	          })();
	          return e.source.postMessage(JSON.stringify({
	            _portal: true,
	            jsonrpc: '2.0',
	            id: id,
	            error: {
	              code: code,
	              message: err.message
	            }
	          }), '*');
	        });
	      } else {
	        if (isValidOrigin(e.origin, this.config.trusted, this.config.allowSubdomains)) {
	          return this.poster.resolveMessage(message);
	        } else {
	          return this.poster.resolveMessage({
	            _portal: true,
	            jsonrpc: '2.0',
	            id: message.id,
	            error: {
	              code: -1,
	              message: "Invalid origin " + e.origin
	            }
	          });
	        }
	      }
	    } catch (_error) {
	      err = _error;
	    }
	  };


	  /*
	   * Register method to be called on child request, or local request fallback
	  
	  @param {String} method
	  @param {Function} fn
	   */

	  PortalGun.prototype.on = function(method, fn) {
	    return this.registeredMethods[method] = fn;
	  };

	  return PortalGun;

	})();

	portal = new PortalGun();

	module.exports = {
	  up: portal.up,
	  down: portal.down,
	  call: portal.call,
	  on: portal.on
	};


/***/ },
/* 1 */
/***/ function(module, exports, __webpack_require__) {

	/* WEBPACK VAR INJECTION */(function(global, module) {(function () {
	  global = this

	  var queueId = 1
	  var queue = {}
	  var isRunningTask = false

	  if (!global.setImmediate)
	    global.addEventListener('message', function (e) {
	      if (e.source == global){
	        if (isRunningTask)
	          nextTick(queue[e.data])
	        else {
	          isRunningTask = true
	          try {
	            queue[e.data]()
	          } catch (e) {}

	          delete queue[e.data]
	          isRunningTask = false
	        }
	      }
	    })

	  function nextTick(fn) {
	    if (global.setImmediate) setImmediate(fn)
	    // if inside of web worker
	    else if (global.importScripts) setTimeout(fn)
	    else {
	      queueId++
	      queue[queueId] = fn
	      global.postMessage(queueId, '*')
	    }
	  }

	  Deferred.resolve = function (value) {
	    if (!(this._d == 1))
	      throw TypeError()

	    return new Deferred(function (resolve) {
	        resolve(value)
	    })
	  }

	  Deferred.reject = function (value) {
	    if (!(this._d == 1))
	      throw TypeError()

	    return new Deferred(function (resolve, reject) {
	        reject(value)
	    })
	  }

	  Deferred.all = function (arr) {
	    if (!(this._d == 1))
	      throw TypeError()

	    if (!(arr instanceof Array))
	      return Deferred.reject(TypeError())

	    var d = new Deferred()

	    function done(e, v) {
	      if (v)
	        return d.resolve(v)

	      if (e)
	        return d.reject(e)

	      var unresolved = arr.reduce(function (cnt, v) {
	        if (v && v.then)
	          return cnt + 1
	        return cnt
	      }, 0)

	      if(unresolved == 0)
	        d.resolve(arr)

	      arr.map(function (v, i) {
	        if (v && v.then)
	          v.then(function (r) {
	            arr[i] = r
	            done()
	            return r
	          }, done)
	      })
	    }

	    done()

	    return d
	  }

	  Deferred.race = function (arr) {
	    if (!(this._d == 1))
	      throw TypeError()

	    if (!(arr instanceof Array))
	      return Deferred.reject(TypeError())

	    if (arr.length == 0)
	      return new Deferred()

	    var d = new Deferred()

	    function done(e, v) {
	      if (v)
	        return d.resolve(v)

	      if (e)
	        return d.reject(e)

	      var unresolved = arr.reduce(function (cnt, v) {
	        if (v && v.then)
	          return cnt + 1
	        return cnt
	      }, 0)

	      if(unresolved == 0)
	        d.resolve(arr)

	      arr.map(function (v, i) {
	        if (v && v.then)
	          v.then(function (r) {
	            done(null, r)
	          }, done)
	      })
	    }

	    done()

	    return d
	  }

	  Deferred._d = 1


	  /**
	   * @constructor
	   */
	  function Deferred(resolver) {
	    if (typeof resolver != 'function' && resolver != undefined)
	      throw TypeError()

	    // states
	    // 0: pending
	    // 1: resolving
	    // 2: rejecting
	    // 3: resolved
	    // 4: rejected
	    var self = this,
	      state = 0,
	      val = 0,
	      next = [],
	      fn, er;

	    self['promise'] = self

	    self['resolve'] = function (v) {
	      fn = this.fn
	      er = this.er
	      if (!state) {
	        val = v
	        state = 1

	        nextTick(fire)
	      }
	      return this
	    }

	    self['reject'] = function (v) {
	      fn = this.fn
	      er = this.er
	      if (!state) {
	        val = v
	        state = 2

	        nextTick(fire)
	      }
	      return this
	    }

	    self['then'] = function (_fn, _er) {
	      var d = new Deferred()
	      d.fn = _fn
	      d.er = _er
	      if (state == 3) {
	        d.resolve(val)
	      }
	      else if (state == 4) {
	        d.reject(val)
	      }
	      else {
	        next.push(d)
	      }
	      return d
	    }

	    self['catch'] = function (_er) {
	      return self['then'](null, _er)
	    }

	    var finish = function (type) {
	      state = type || 4
	      next.map(function (p) {
	        state == 3 && p.resolve(val) || p.reject(val)
	      })
	    }

	    try {
	      if (typeof resolver == 'function')
	        resolver(self['resolve'], self['reject'])
	    } catch (e) {
	      self['reject'](e)
	    }

	    return self

	    // ref : reference to 'then' function
	    // cb, ec, cn : successCallback, failureCallback, notThennableCallback
	    function thennable (ref, cb, ec, cn) {
	      if ((typeof val == 'object' || typeof val == 'function') && typeof ref == 'function') {
	        try {

	          // cnt protects against abuse calls from spec checker
	          var cnt = 0
	          ref.call(val, function (v) {
	            if (cnt++) return
	            val = v
	            cb()
	          }, function (v) {
	            if (cnt++) return
	            val = v
	            ec()
	          })
	        } catch (e) {
	          val = e
	          ec()
	        }
	      } else {
	        cn()
	      }
	    };

	    function fire() {

	      // check if it's a thenable
	      var ref;
	      try {
	        ref = val && val.then
	      } catch (e) {
	        val = e
	        state = 2
	        return fire()
	      }

	      thennable(ref, function () {
	        state = 1
	        fire()
	      }, function () {
	        state = 2
	        fire()
	      }, function () {
	        try {
	          if (state == 1 && typeof fn == 'function') {
	            val = fn(val)
	          }

	          else if (state == 2 && typeof er == 'function') {
	            val = er(val)
	            state = 1
	          }
	        } catch (e) {
	          val = e
	          return finish()
	        }

	        if (val == self) {
	          val = TypeError()
	          finish()
	        } else thennable(ref, function () {
	            finish(3)
	          }, finish, function () {
	            finish(state == 1 && 3)
	          })

	      })
	    }


	  }

	  // Export our library object, either for node.js or as a globally scoped variable
	  if (true) {
	    module['exports'] = Deferred
	  } else {
	    global['Promise'] = global['Promise'] || Deferred
	  }
	})()
	
	/* WEBPACK VAR INJECTION */}.call(exports, (function() { return this; }()), __webpack_require__(2)(module)))

/***/ },
/* 2 */
/***/ function(module, exports, __webpack_require__) {

	module.exports = function(module) {
		if(!module.webpackPolyfill) {
			module.deprecate = function() {};
			module.paths = [];
			// module.parent = undefined by default
			module.children = [];
			module.webpackPolyfill = 1;
		}
		return module;
	}


/***/ }
/******/ ])