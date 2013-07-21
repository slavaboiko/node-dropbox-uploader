# OAuth driver that uses a Cordova InAppBrowser to complete the flow.
class Dropbox.AuthDriver.Cordova extends Dropbox.AuthDriver.BrowserBase
  # Sets up an OAuth driver for Cordova applications.
  #
  # @param {Object} options (optional) one of the settings below
  # @option options {String} scope embedded in the localStorage key that holds
  #   the authentication data; useful for having multiple OAuth tokens in a
  #   single application
  # @option options {Boolean} rememberUser if false, the user's OAuth tokens
  #   are not saved in localStorage; true by default
  constructor: (options) ->
    if options
      @rememberUser = if 'rememberUser' of options
        options.rememberUser
      else
        true
      @scope = options.scope or 'default'
    else
      @rememberUser = true
      @scope = 'default'
    @scope = options?.scope or 'default'

  # Shows the authorization URL in a pop-up, waits for it to send a message.
  #
  # @see Dropbox.AuthDriver#doAuthorize
  doAuthorize: (authUrl, stateParam, client, callback) ->
    browser = window.open authUrl, '_blank', 'location=yes'
    promptPageLoaded = false
    authHost = /^[^/]*\/\/[^/]*\//.exec(authUrl)[0]
    onEvent = (event) ->
      if event.url is authUrl and promptPageLoaded is false
        # We get loadstop for the app authorization prompt page.
        # On phones, we get a 2nd loadstop for the same authorization URL
        # when the user clicks 'Allow'. On tablets, we get a different URL.
        promptPageLoaded = true
        return
      if event.url and event.url.substring(0, authHost.length) isnt authHost
        # The user clicked on the app URL. Wait until they come back.
        promptPageLoaded = false
        return
      if event.type is 'exit' or promptPageLoaded
        browser.removeEventListener 'loadstop', onEvent
        browser.removeEventListener 'exit', onEvent
        browser.close() unless event.type is 'exit'
        callback()
    browser.addEventListener 'loadstop', onEvent
    browser.addEventListener 'exit', onEvent

  # This driver does not use a redirect page.
  #
  # @see Dropbox.AuthDriver#url
  url: -> null
