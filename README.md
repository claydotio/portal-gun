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

@param {Object} config
@param {String} config.trusted - trusted domain name e.g. 'clay.io'
@param {Boolean} config.subdomains - trust subdomains of trusted domain
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

## Contributing

##### Install pre-commit hook

`ln -s ../../pre-commit.sh .git/hooks/pre-commit`

```bash
npm install
npm test
```
