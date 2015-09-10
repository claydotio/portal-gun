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
  isParentValidFn: (origin) ->
    return origin is 'http://x.com'
})

portal.listen()

portal.on 'methodName', (what) -> "#{what}?"

portal.call 'methodName', 'hello'
.then (result) -> # 'hello?'
```

```coffee
###
# @param {Object} config
# @param {Number} [config.timeout=3000] - request timeout (ms)
# @param {Function<Boolean>} config.isParentValidFn - restrict parent origin
###
constructor: ({timeout, @isParentValidFn} = {}) -> null

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

v0.3.0 -> v0.4.0
  - removed `trusted` and `allowSubdomains` config
  - added `isParentValidFn`

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
