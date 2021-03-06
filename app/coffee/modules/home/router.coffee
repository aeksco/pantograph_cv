HomeRoute = require './home/route'

# # # # #

# HomeRouter class definition
class HomeRouter extends require 'hn_routing/lib/router'

  routes:
    '(/)':  'home'

  home: ->
    new HomeRoute({ container: @container })

# # # # #

module.exports = HomeRouter
