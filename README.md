# Portal-Gun

### An iframe rpc library

## Install

```bash
$ npm install portal-gun
```

## API

`portal = require('portal-gun')`  
`portal.up`  
`portal.down`  
`portal.call`  
`portal.on`  

```coffee
###
# Bind global message event listener

@param {Object} [config]
@param {Array<String>} config.trusted - trusted domains e.g.['clay.io']
@param {Boolean} config.allowSubdomains - trust subdomains of trusted domain
###
up: (config) =>
```

```coffee
# Remove global message event listener
down: =>
```

```coffee
###
@param {String} method
@param {*} params - Arrays will be deconstructed as multiple args
###
call: (method, params = []) =>
```

```coffee
###
# Register method to be called on child request, or local request fallback

@param {String} method
@param {Function} fn
###
on: (method, fn) =>
```

## Contributing

```bash
npm install
npm test
```

## Changelog

v0.1.x -> v0.2.0

  - added callback support (currently one-way)
  - removed `beforeWindowOpen` and `windowOpen`
  - `trusted` domains must be an array
  - removed `timeout` config
  - `subdomains` config renamed to `allowSubdomains`
  - renamed `register()` -> `on()`
  - renamed `get()` -> `call()`
