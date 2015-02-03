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

	var IS_FRAMED, PortalGun, Poster, Promise, REQUEST_TIMEOUT_MS, deferredFactory, portal,
	  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

	Promise = window.Promise || __webpack_require__(1);

	IS_FRAMED = window.self !== window.top;

	REQUEST_TIMEOUT_MS = 950;

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


	/*
	 * Messages follow the json-rpc 2.0 spec: http://www.jsonrpc.org/specification
	 * _portal is added to denote a portal-gun message

	@typedef {Object} RPCRequest
	@property {Integer} [id] - Without an `id` this is a notification
	@property {String} method
	@property {Array<*>} params
	@property {Boolean} _clay - Must be true
	@property {String} jsonrpc - Must be '2.0'

	@typedef {Object} RPCResponse
	@property {Integer} [id]
	@property {*} result
	@property {RPCError} error

	@typedef {Object} RPCError
	@property {Integer} code
	@property {String} message
	 */

	Poster = (function() {
	  function Poster(timeout) {
	    this.timeout = timeout;
	    this.resolveMessage = __bind(this.resolveMessage, this);
	    this.postMessage = __bind(this.postMessage, this);
	    this.setTimeout = __bind(this.setTimeout, this);
	    this.lastMessageId = 0;
	    this.pendingMessages = {};
	  }

	  Poster.prototype.setTimeout = function(timeout) {
	    this.timeout = timeout;
	    return null;
	  };


	  /*
	  @param {String} method
	  @param {Array} [params]
	  @returns {Promise}
	   */

	  Poster.prototype.postMessage = function(method, params) {
	    var deferred, err, id, message;
	    if (params == null) {
	      params = [];
	    }
	    deferred = deferredFactory();
	    message = {
	      method: method,
	      params: params
	    };
	    try {
	      this.lastMessageId += 1;
	      id = this.lastMessageId;
	      message.id = id;
	      message._portal = true;
	      message.jsonrpc = '2.0';
	      this.pendingMessages[message.id] = deferred;
	      window.parent.postMessage(JSON.stringify(message), '*');
	    } catch (_error) {
	      err = _error;
	      deferred.reject(err);
	    }
	    window.setTimeout(function() {
	      return deferred.reject(new Error('Message Timeout'));
	    }, this.timeout);
	    return deferred;
	  };


	  /*
	  @param {RPCResponse|RPCError}
	   */

	  Poster.prototype.resolveMessage = function(message) {
	    if (!this.pendingMessages[message.id]) {
	      return Promise.reject('Method not found');
	    } else if (message.error) {
	      return this.pendingMessages[message.id].reject(new Error(message.error.message));
	    } else {
	      return this.pendingMessages[message.id].resolve(message.result || null);
	    }
	  };

	  return Poster;

	})();

	PortalGun = (function() {
	  function PortalGun() {
	    this.register = __bind(this.register, this);
	    this.onMessage = __bind(this.onMessage, this);
	    this.isValidOrigin = __bind(this.isValidOrigin, this);
	    this.validateParent = __bind(this.validateParent, this);
	    this.windowOpen = __bind(this.windowOpen, this);
	    this.beforeWindowOpen = __bind(this.beforeWindowOpen, this);
	    this.get = __bind(this.get, this);
	    this.down = __bind(this.down, this);
	    this.up = __bind(this.up, this);
	    this.config = {
	      trusted: null,
	      subdomains: false,
	      timeout: REQUEST_TIMEOUT_MS
	    };
	    this.windowOpenQueue = [];
	    this.poster = new Poster({
	      timeout: this.config.timeout
	    });
	    this.registeredMethods = {
	      ping: function() {
	        return 'pong';
	      }
	    };
	  }


	  /*
	   * Bind global message event listener
	  
	  @param {Object} config
	  @param {String} config.trusted - trusted domain name e.g. 'clay.io'
	  @param {Boolean} config.subdomains - trust subdomains of trusted domain
	  @param {Number} config.timeout - global message timeout
	   */

	  PortalGun.prototype.up = function(_arg) {
	    var subdomains, timeout, trusted, _ref;
	    _ref = _arg != null ? _arg : {}, trusted = _ref.trusted, subdomains = _ref.subdomains, timeout = _ref.timeout;
	    if (trusted !== void 0) {
	      this.config.trusted = trusted;
	    }
	    if (subdomains != null) {
	      this.config.subdomains = subdomains;
	    }
	    if (timeout != null) {
	      this.config.timeout = timeout;
	    }
	    this.poster.setTimeout(this.config.timeout);
	    return window.addEventListener('message', this.onMessage);
	  };

	  PortalGun.prototype.down = function() {
	    return window.removeEventListener('message', this.onMessage);
	  };


	  /*
	  @param {String} method
	  @param {Array} [params]
	   */

	  PortalGun.prototype.get = function(method, params) {
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
	        fn = _this.registeredMethods[method] || function() {
	          throw new Error('Method not found');
	        };
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

	  PortalGun.prototype.beforeWindowOpen = function() {
	    var ms, _i, _results;
	    _results = [];
	    for (ms = _i = 0; _i <= 1000; ms = _i += 10) {
	      _results.push(setTimeout((function(_this) {
	        return function() {
	          var url, _j, _len, _ref;
	          _ref = _this.windowOpenQueue;
	          for (_j = 0, _len = _ref.length; _j < _len; _j++) {
	            url = _ref[_j];
	            window.open(url);
	          }
	          return _this.windowOpenQueue = [];
	        };
	      })(this), ms));
	    }
	    return _results;
	  };


	  /*
	   * Must be called after beginWindowOpen, and not later than 1 second after
	  @param {String} url
	   */

	  PortalGun.prototype.windowOpen = function(url) {
	    return this.windowOpenQueue.push(url);
	  };

	  PortalGun.prototype.validateParent = function() {
	    return this.poster.postMessage('ping');
	  };

	  PortalGun.prototype.isValidOrigin = function(origin) {
	    var regex, _ref;
	    if (!((_ref = this.config) != null ? _ref.trusted : void 0)) {
	      return true;
	    }
	    regex = this.config.subdomains ? new RegExp('^https?://(\\w+\\.)?(\\w+\\.)?' + ("" + (this.config.trusted.replace(/\./g, '\\.')) + "/?$")) : new RegExp('^https?://' + ("" + (this.config.trusted.replace(/\./g, '\\.')) + "/?$"));
	    return regex.test(origin);
	  };

	  PortalGun.prototype.onMessage = function(e) {
	    var err, id, isRequest, message, method, params;
	    try {
	      message = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
	      if (!message._portal) {
	        throw new Error('Non-portal message');
	      }
	      isRequest = !!message.method;
	      if (isRequest) {
	        id = message.id, method = message.method, params = message.params;
	        return this.get(method, params).then(function(result) {
	          message = {
	            id: id,
	            result: result,
	            _portal: true,
	            jsonrpc: '2.0'
	          };
	          return e.source.postMessage(JSON.stringify(message), '*');
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
	          message = {
	            _portal: true,
	            jsonrpc: '2.0',
	            id: id,
	            error: {
	              code: code,
	              message: err.message
	            }
	          };
	          return e.source.postMessage(JSON.stringify(message), '*');
	        });
	      } else {
	        if (!this.isValidOrigin(e.origin)) {
	          message.error = {
	            message: "Invalid origin " + e.origin,
	            code: -1
	          };
	        }
	        return this.poster.resolveMessage(message);
	      }
	    } catch (_error) {
	      err = _error;
	      console.log(err);
	    }
	  };


	  /*
	   * Register method to be called on child request, or local request fallback
	  
	  @param {String} method
	  @param {Function} fn
	   */

	  PortalGun.prototype.register = function(method, fn) {
	    return this.registeredMethods[method] = fn;
	  };

	  return PortalGun;

	})();

	portal = new PortalGun();

	module.exports = {
	  up: portal.up,
	  down: portal.down,
	  get: portal.get,
	  register: portal.register,
	  beforeWindowOpen: portal.beforeWindowOpen,
	  windowOpen: portal.windowOpen
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