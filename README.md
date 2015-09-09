# Portal-Gun

### An iframe rpc library

## Install

```bash
$ npm install portal-gun
```

## API

```coffee
PortalGun = require 'portal-gun'

portal = new PortalGun({
  trusted: ['x.com']
  allowSubdomains: true
})

portal.listen()

portal.on 'methodName', (what) -> "#{what}?"

portal.call 'methodName', 'hello'
.then (result) -> # 'hello?'
```

```coffee
###
# @param {Object} config
# @param {Number} config.timeout - request timeout (ms)
# @param {Array<String>|Null} config.trusted - trusted domains e.g. ['clay.io']
# @param {Boolean} config.allowSubdomains - trust subdomains of trusted domain
###
constructor: ({timeout, @trusted, @allowSubdomains} = {}) -> null

# Binds global message listener
# Must be called before .call()
listen: =>

###
# @param {String} method
# @param {...*} params
# @returns Promise
###
call: (method, params...) =>

###
# Register method to be called on child request, or local request fallback
# @param {String} method
# @param {Function} fn
###
on: (method, fn) =>
```

## Contributing

```bash
npm install
npm test
```

## Changelog

v0.2.0 -> v0.3.0
  - new class api
  - compatible with v0.2.0 RPC spec
  - improved testing, stability, and timeout guarantees

v0.1.x -> v0.2.0

  - added callback support (currently one-way)
  - removed `beforeWindowOpen` and `windowOpen`
  - `trusted` domains must be an array
  - removed `timeout` config
  - `subdomains` config renamed to `allowSubdomains`
  - renamed `register()` -> `on()`
  - renamed `get()` -> `call()`
