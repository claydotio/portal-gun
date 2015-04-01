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
`portal.get`  
`portal.register`  

```coffee
###
# Bind global message event listener

@param {Object} [config]
@param {String|Array<String>} config.trusted - trusted domains e.g.['clay.io']
@param {Boolean} config.subdomains - trust subdomains of trusted domain
@param {Number} config.timeout - global message timeout
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
@param {Array} [params]
###
get: (method, params = []) =>
```

```coffee
###
# Register method to be called on child request, or local request fallback

@param {String} method
@param {Function} fn
###
register: (method, fn) =>
```

```coffee
# Must be called in the same tick as an interaction event
beforeWindowOpen: =>

###
# Must be called after beginWindowOpen, and not later than 1 second after
# params: https://developer.mozilla.org/en-US/docs/Web/API/Window.open
###
windowOpen: (url, windowName, strWindowFeatures) =>
```

## Contributing

##### Install pre-commit hook

`ln -s ../../pre-commit.sh .git/hooks/pre-commit`

```bash
npm install
npm test
```
