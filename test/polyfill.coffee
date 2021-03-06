if window?
  # Function::bind polyfill for rewirejs + phantomjs
  # coffeelint: disable=missing_fat_arrows
  unless Function::bind
    Function::bind = (oThis) ->

      # closest thing possible to the ECMAScript 5
      # internal IsCallable function
      throw new TypeError('Function.prototype.bind - what is trying to be bound
       is not callable')  if typeof this isnt 'function'
      aArgs = Array::slice.call(arguments, 1)
      fToBind = this
      fNOP = -> null

      fBound = ->
        fToBind.apply (if this instanceof fNOP and oThis then this else oThis),
        aArgs.concat(Array::slice.call(arguments))

      fNOP.prototype = this.prototype
      fBound:: = new fNOP()
      fBound
  # coffeelint: enable=missing_fat_arrows
