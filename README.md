# Portal-Gun

### An iframe rpc library

## Install

```bash
$ npm install portal-gun
```

## API

`portal = require('portal-gun')`  
`porta.up`  
`porta.down`  
`porta.get`  
`porta.register`  

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

  # params should always be an array
  unless Object::toString.call(params) is '[object Array]'
    params = [params]

  localMethod = (method, params) =>
    fn = @registerdMethods[method] or -> throw new Error 'Method not found'
    return fn.apply null, params

  if IS_FRAMED
    frameError = null
    @validateParent()
    .then =>
      @poster.postMessage method, params
    .catch (err) ->
      frameError = err
      return localMethod method, params
    .catch (err) ->
      if err.message is 'Method not found' and frameError isnt null
        throw frameError
      else
        throw err
  else
    new Promise (resolve) ->
      resolve localMethod(method, params)
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
