{Disposable} = require 'atom'
{$, ScrollView} = require 'atom-space-pen-views'
PhpDebugContextView = require '../context/php-debug-context-view'
PhpDebugStackView = require '../stack/php-debug-stack-view'
PhpDebugWatchView = require '../watch/php-debug-watch-view'
PhpDebugBreakpointView = require '../breakpoint/php-debug-breakpoint-view'
Interact = require('interact.js')
module.exports =
class PhpDebugUnifiedView extends ScrollView
  @content: ->
    @div class: 'php-debug', tabindex: -1, =>
      @div class: 'php-debug-unified-view', =>
        @div class: 'block action-bar', =>
          @button class: "btn btn-action octicon icon-playback-play inline-block-tight",    disabled: 'disabled', 'data-action':'continue', =>
            @span class: "btn-text", "Continue"
          @button class: "btn btn-action octicon icon-steps inline-block-tight",            disabled: 'disabled', 'data-action':'step', =>
            @span class: "btn-text", "Step Over"
          @button class: "btn btn-action octicon icon-sign-in inline-block-tight",          disabled: 'disabled', 'data-action':'in', =>
            @span class: "btn-text", "Step In"
          @button class: "btn btn-action octicon icon-sign-out inline-block-tight",         disabled: 'disabled', 'data-action':'out', =>
            @span class: "btn-text", "Step Out"
          @button class: "btn btn-action octicon icon-primitive-square inline-block-tight", disabled: 'disabled', 'data-action':'stop', =>
            @span class: "btn-text",  "Stop"
          @span outlet: 'connectStatus'
          @button class: "btn view-mode-btn view-mode-btn-side mdi mdi-rotate-right-variant inline-block-tight", 'data-action':'setmode-side', ""
          @button class: "btn view-mode-btn view-mode-btn-bottom mdi mdi-rotate-left-variant inline-block-tight", style: 'transform: rotate(-90deg)', 'data-action':'setmode-bottom', ""
        @div class: 'tabs-wrapper', outlet:'tabsWrapper', =>
          @div class: 'tabs-view', =>
            @div outlet: 'stackView', class:'php-debug-tab'
            @div outlet: 'contextView', class:'php-debug-tab'
            @div outlet: 'watchpointView', class:'php-debug-tab'
            @div outlet: 'breakpointView', class:'php-debug-tab'

  constructor: (params) ->
    super
    @GlobalContext = params.context
    @contextList = []
    @GlobalContext.onBreak () =>
      @find('button').enable()
    @GlobalContext.onRunning () =>
      @find('button').disable()
    @GlobalContext.onSessionEnd () =>
      @find('button').disable()

    @panelMode = atom.config.get('php-debug.currentPanelMode')
    @resizeType = { top: true, left:false }
    if (!@panelMode)
      @panelMode = "bottom"

    switch @panelMode
      when "side"
        @resizeType = { top: false, left:true }

    @resizer = Interact(this.element)
    @resizer = @resizer.resizable({edges: @resizeType})

    @resizer = @resizer.on('resizemove', (event) =>

        target = event.target
        if event.rect.height < 25
          if event.rect.height < 1
            target.style.width = target.style.height = null
          else
            return # No-Op
        if event.rect.width < 262
          if event.rect.width < 1
            target.style.width = target.style.height = null
          else
            return # No-Op
        else
          $(@.element).removeClass('narrow')
          if (@panelMode == "side")
            if (event.rect.width < 408)
              $(@.element).addClass('narrow')

          target.style.width  = event.rect.width + 'px'
          target.style.height = event.rect.height + 'px'
          if (@panelMode == "bottom")
            @find('.tabs-wrapper').css('height',event.rect.height + 'px')
          else
            @find('.tabs-wrapper').css('width',event.rect.width + 'px')
      )
    @resizer = @resizer.on('resizeend', (event) =>
        console.log('caled')
        if (@panelMode == "bottom")
          event.target.style.width = 'auto'
          atom.config.set('php-debug.currentPanelHeight',event.target.style.height);
        else
          event.target.style.height = 'auto'
          atom.config.set('php-debug.currentPanelWidth',event.target.style.width);

      )


    @visible = false
    @setPanelMode(@panelMode)
    @setConnected(false)

  serialize: ->
    deserializer: @constructor.name
    uri: @getURI()

  getURI: -> @uri

  getTitle: -> "Debugging"

  setPanelMode: (type) =>
    atom.config.set('php-debug.currentPanelMode',type)
    @find('.php-debug').removeClass('panel-mode-'+@panelMode)
    @resizeType = { top: true, left:false }
    switch type
      when "side"
        if (@panel)
          @panel.destroy()
        width = atom.config.get('php-debug.currentPanelWidth')
        if (!width)
          width = '140px'
        @find('.view-mode-btn-side').attr({disabled:true});
        @find('.view-mode-btn-bottom').attr({disabled:false});
        @find('.tabs-wrapper').css('width',width)
        $(this.element).css('width',width)
        @find('.tabs-wrapper').css('height','auto')
        $(this.element).css('height','auto')
        @panel = atom.workspace.addRightPanel({item: this.element, visible: @visible, priority: 400})
        @panelMode = "side"
        @resizeType = { left: true, top: false }
      else
        if (@panel)
          @panel.destroy()
        height = atom.config.get('php-debug.currentPanelHeight')
        if (!height)
          height = '250px';
        @find('.view-mode-btn-bottom').attr({disabled:true});
        @find('.view-mode-btn-side').attr({disabled:false});
        @find('.tabs-wrapper').css('height',height)
        $(this.element).css('height',height)
        @find('.tabs-wrapper').css('width','auto')
        $(this.element).css('width','auto')
        @panel = atom.workspace.addBottomPanel({item: this.element, visible: @visible, priority: 400})
        @panelMode = "bottom"

    @find('.php-debug').addClass('panel-mode-'+@panelMode)
    @resizer = @resizer.resizable({edges: @resizeType})

  setConnected: (isConnected) =>
    if (@panel?.item?.clientHeight > 0)
      @panel?.item?.style.height = @panel?.item?.clientHeight + 'px'
      @find('.tabs-wrapper').css('height',@panel?.item?.clientHeight + 'px')

    if isConnected
      @connectStatus.text('Connected')
    else
      serverPort = atom.config.get('php-debug.ServerPort')
      @connectStatus.text("Listening on port #{serverPort}...")

  setVisible: (@visible) =>

    if @visible
      @panel.show()
      serverPort = atom.config.get('php-debug.ServerPort')
      @connectStatus.text("Listening on port #{serverPort}...")
    else
      @panel.hide()

  isVisible: () =>
    @visible

  initialize: (params) =>
    super
    @stackView.append(new PhpDebugStackView(context: params.context))
    @contextView.append(new PhpDebugContextView(context: params.context))
    @watchpointView.append(new PhpDebugWatchView(context: params.context))
    @breakpointView.append(new PhpDebugBreakpointView(context: params.context))

    @on 'click', '[data-action]', (e) =>
      action = e.target.getAttribute('data-action')
      switch action
        when 'continue'
          @GlobalContext.getCurrentDebugContext().continue "run"
        when 'step'
          @GlobalContext.getCurrentDebugContext().continue "step_over"
        when 'in'
          @GlobalContext.getCurrentDebugContext().continue "step_into"
        when 'out'
          @GlobalContext.getCurrentDebugContext().continue "step_out"
        when 'stop'
          @GlobalContext.getCurrentDebugContext().executeDetach()
        when 'setmode-bottom'
          @setPanelMode('bottom')
        when 'setmode-side'
          @setPanelMode('side')

        else
          console.error "unknown action"
          console.dir action
          console.dir this


  onDidChangeTitle: -> new Disposable ->
  onDidChangeModified: -> new Disposable ->

  destroy: =>
    if @GlobalContext.getCurrentDebugContext()
      @GlobalContext.getCurrentDebugContext().executeDetach()

  isEqual: (other) ->
    other instanceof PhpDebugUnifiedView
