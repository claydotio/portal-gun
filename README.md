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

(alias `get` - deprecated)
```coffee
###
@param {String} method
@param {Array} [params]
###
call: (method, params = []) =>
```

(alias `register` - deprecated)
```coffee
###
# Register method to be called on child request, or local request fallback

@param {String} method
@param {Function} fn
###
on: (method, fn) =>
```

## Contributing

##### Install pre-commit hook

`ln -s ../../pre-commit.sh .git/hooks/pre-commit`

```bash
npm install
npm test
```

## Changelog

v0.1.3 - 0.2.0

  - removed `beforeWindowOpen` and `windowOpen`
  - `trusted` domains must be an array
  - removed `timeout` config
  - `subdomains` config renamed to `allowSubdomains`
