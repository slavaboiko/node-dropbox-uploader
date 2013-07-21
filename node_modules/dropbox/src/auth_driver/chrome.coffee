DropboxChromeOnMessage = null
DropboxChromeSendMessage = null

if chrome?
  # v2 manifest APIs.
  if chrome.runtime
    if chrome.runtime.onMessage
      DropboxChromeOnMessage = chrome.runtime.onMessage
    if chrome.runtime.sendMessage
      DropboxChromeSendMessage = (m) -> chrome.runtime.sendMessage m

  # v1 manifest APIs.
  if chrome.extension
    if chrome.extension.onMessage
      DropboxChromeOnMessage or= chrome.extension.onMessage
    if chrome.extension.sendMessage
      DropboxChromeSendMessage or= (m) -> chrome.extension.sendMessage m

  # Apps that use the v2 manifest don't get messenging in Chrome 25.
  unless DropboxChromeOnMessage
    do ->
      pageHack = (page) ->
        if page.Dropbox
          Dropbox.AuthDriver.Chrome::onMessage =
              page.Dropbox.AuthDriver.Chrome.onMessage
          Dropbox.AuthDriver.Chrome::sendMessage =
              page.Dropbox.AuthDriver.Chrome.sendMessage
        else
          page.Dropbox = Dropbox
          Dropbox.AuthDriver.Chrome::onMessage = new Dropbox.Util.EventSource
          Dropbox.AuthDriver.Chrome::sendMessage =
              (m) -> Dropbox.AuthDriver.Chrome::onMessage.dispatch m

      if chrome.extension and chrome.extension.getBackgroundPage
        if page = chrome.extension.getBackgroundPage()
          return pageHack(page)

      if chrome.runtime and chrome.runtime.getBackgroundPage
        return chrome.runtime.getBackgroundPage (page) -> pageHack page

# OAuth driver specialized for Chrome apps and extensions.
class Dropbox.AuthDriver.Chrome extends Dropbox.AuthDriver.BrowserBase
  # @property {Chrome.Event<Object>, Dropbox.Util.EventSource<Object>} fires
  #   non-cancelable events when Dropbox.AuthDriver.Chrome#sendMessage is
  #   called; the message is a parsed JSON object
  #
  # @private
  # This should only be used to communicate between
  # {Dropbox.AuthDriver.Chrome#doAuthorize} and
  # {Dropbox.AuthDriver.Chrome.oauthReceiver}.
  onMessage: DropboxChromeOnMessage

  # Sends a message across the Chrome extension / application.
  #
  # This causes {Dropbox.AuthDriver.Chrome#onMessage} to fire an event
  # containing the given message.
  #
  # @private
  # This should only be used to communicate between
  # {Dropbox.AuthDriver.Chrome#doAuthorize} and
  # {Dropbox.AuthDriver.Chrome.oauthReceiver}.
  #
  # @param {Object} message an object that can be serialized to JSON
  # @return unspecified; may vary across platforms and dropbox.js versions
  sendMessage: DropboxChromeSendMessage

  # Expands an URL relative to the Chrome extension / application root.
  #
  # @param {String} url a resource URL relative to the extension root
  # @return {String} the absolute resource URL
  expandUrl: (url) ->
    if chrome.runtime and chrome.runtime.getURL
      return chrome.runtime.getURL(url)
    if chrome.extension and chrome.extension.getURL
      return chrome.extension.getURL(url)
    url

  # Sets up an OAuth driver for Chrome.
  #
  # @param {Object} options (optional) one or more of the options below
  # @option options {String} receiverPath the path of page that receives the
  #   /authorize redirect and calls {Dropbox.AuthDriver.Chrome.oauthReceiver};
  #   the path should be relative to the extension folder; by default, is
  #   'chrome_oauth_receiver.html'
  constructor: (options) ->
    super options
    receiverPath = (options and options.receiverPath) or
        'chrome_oauth_receiver.html'
    @useQuery = true
    @receiverUrl = @expandUrl receiverPath
    @storageKey = "dropbox_js_#{@scope}_credentials"

  # Saves token information when appropriate.
  onAuthStepChange: (client, callback) ->
    switch client.authStep
      when Dropbox.Client.RESET
        @loadCredentials (credentials) =>
          if credentials
            if credentials.authStep
              # Stuck authentication process, reset.
              return @forgetCredentials(callback)
            client.setCredentials credentials
          callback()
      when Dropbox.Client.DONE
        @storeCredentials client.credentials(), callback
      when Dropbox.Client.SIGNED_OUT
        @forgetCredentials callback
      when Dropbox.Client.ERROR
        @forgetCredentials callback
      else
        callback()

  # Shows the authorization URL in a new tab, waits for it to send a message.
  #
  # @see Dropbox.AuthDriver#doAuthorize
  doAuthorize: (authUrl, stateParam, client, callback) ->
    if chrome.identity?.launchWebAuthFlow
      # Apps V2 after the identity API hits stable?
      chrome.identity.launchWebAuthFlow url: authUrl, interactive: true,
          (redirectUrl) =>
            if @locationStateParam(redirectUrl) is stateParam
              stateParam = false  # Avoid having this matched in the future.
              callback Dropbox.Util.Oauth.queryParamsFromUrl(redirectUrl)
    else if chrome.experimental?.identity?.launchWebAuthFlow
      # Apps V2 with identity in experimental
      chrome.experimental.identity.launchWebAuthFlow
          url: authUrl, interactive: true, (redirectUrl) =>
            if @locationStateParam(redirectUrl) is stateParam
              stateParam = false  # Avoid having this matched in the future.
              callback Dropbox.Util.Oauth.queryParamsFromUrl(redirectUrl)
    else
      # Extensions and Apps V1.
      window = handle: null
      @listenForMessage stateParam, window, callback
      @openWindow authUrl, (handle) -> window.handle = handle

  # Creates a popup window.
  #
  # @param {String} url the URL that will be loaded in the popup window
  # @param {function(Object)} callback called with a handle that can be passed
  #   to Dropbox.AuthDriver.Chrome#closeWindow
  # @return {Dropbox.AuthDriver.Chrome} this
  openWindow: (url, callback) ->
    if chrome.tabs and chrome.tabs.create
      chrome.tabs.create url: url, active: true, pinned: false, (tab) ->
        callback tab
      return @
    @

  # Closes a window that was previously opened with openWindow.
  #
  # @private
  # This should only be used by {Dropbox.AuthDriver.Chrome#oauthReceiver}.
  #
  # @param {Object} handle the object passed to an openWindow callback
  closeWindow: (handle) ->
    if chrome.tabs and chrome.tabs.remove and handle.id
      chrome.tabs.remove handle.id
      return @
    if chrome.app and chrome.app.window and handle.close
      handle.close()
      return @
    @

  # URL of the redirect receiver page that messages the app / extension.
  #
  # @see Dropbox.AuthDriver#url
  url: ->
    @receiverUrl

  # Listens for a postMessage from a previously opened tab.
  #
  # @private
  # This should only be used by {Dropbox.AuthDriver.Chrome#doAuthorize}.
  #
  # @param {String} stateParam the state parameter passed to the OAuth 2
  #   /authorize endpoint
  # @param {Object} window a JavaScript object whose "handle" property is a
  #   window handle passed to the callback of a
  #   Dropbox.AuthDriver.Chrome#openWindow call
  # @param {function()} called when the received message matches stateParam
  listenForMessage: (stateParam, window, callback) ->
    listener = (message, sender) =>
      # Reject messages not coming from the OAuth receiver window.
      if sender and sender.tab
        unless sender.tab.url.substring(0, @receiverUrl.length) is @receiverUrl
          return

      # Reject improperly formatted messages.
      return unless message.dropbox_oauth_receiver_href

      receiverHref = message.dropbox_oauth_receiver_href
      if @locationStateParam(receiverHref) is stateParam
        stateParam = false  # Avoid having this matched in the future.
        @closeWindow window.handle if window.handle
        @onMessage.removeListener listener
        callback Dropbox.Util.Oauth.queryParamsFromUrl(receiverHref)
    @onMessage.addListener listener

  # Stores a Dropbox.Client's credentials in local storage.
  #
  # @private
  # onAuthStepChange calls this method during the authentication flow.
  #
  # @param {Object} credentials the result of a Drobpox.Client#credentials call
  # @param {function()} callback called when the storing operation is complete
  # @return {Dropbox.AuthDriver.BrowserBase} this, for easy call chaining
  storeCredentials: (credentials, callback) ->
    items= {}
    items[@storageKey] = credentials
    chrome.storage.local.set items, callback
    @

  # Retrieves a token and secret from localStorage.
  #
  # @private
  # onAuthStepChange calls this method during the authentication flow.
  #
  # @param {function(?Object)} callback supplied with the credentials object
  #   stored by a previous call to
  #   Dropbox.AuthDriver.BrowserBase#storeCredentials; null if no credentials
  #   were stored, or if the previously stored credentials were deleted
  # @return {Dropbox.AuthDriver.BrowserBase} this, for easy call chaining
  loadCredentials: (callback) ->
    chrome.storage.local.get @storageKey, (items) =>
      callback items[@storageKey] or null
    @

  # Deletes information previously stored by a call to storeCredentials.
  #
  # @private
  # onAuthStepChange calls this method during the authentication flow.
  #
  # @param {function()} callback called after the credentials are deleted
  # @return {Dropbox.AuthDriver.BrowserBase} this, for easy call chaining
  forgetCredentials: (callback) ->
    chrome.storage.local.remove @storageKey, callback
    @

  # Communicates with the driver from the OAuth receiver page.
  #
  # The easiest way for a Chrome application or extension to keep up to date
  # with dropbox.js is to set up a popup receiver page that loads dropbox.js
  # and calls this method. This guarantees that the code used to communicate
  # between the popup receiver page and {Dropbox.AuthDriver.Popup#doAuthorize}
  # stays up to date as dropbox.js is updated.
  @oauthReceiver: ->
    window.addEventListener 'load', ->
      driver = new Dropbox.AuthDriver.Chrome()
      pageUrl = window.location.href
      window.location.hash = ''  # Remove the token from the browser history.
      driver.sendMessage dropbox_oauth_receiver_href: pageUrl
      window.close() if window.close
