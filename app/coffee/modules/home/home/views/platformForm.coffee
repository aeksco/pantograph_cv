
class PlatformForm extends Marionette.LayoutView
  template: require './templates/platform_form'
  className: 'row'

  behaviors:
    Form: {}
    RangeSlider: {}
    BootstrapSwitch: {}

  modelEvents:
    'change': 'onModelChange'

  onModelChange: ->
    @model.parent.trigger('child:change')

  onSwitchChange: ->
    @updateAttrs()

# # # # #

module.exports = PlatformForm
