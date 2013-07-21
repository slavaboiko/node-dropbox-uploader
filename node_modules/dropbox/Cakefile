async = require 'async'
fs = require 'fs-extra'
glob = require 'glob'
path = require 'path'
watch = require 'watch'

download = require './tasks/download'
siteDoc = require './tasks/site_doc'
run = require './tasks/run'


# Node 0.6 compatibility hack.
unless fs.existsSync
  fs.existsSync = (filePath) -> path.existsSync filePath


task 'build', ->
  clean ->
    build ->
      buildPackage()

task 'clean', ->
  clean()

task 'watch', ->
  setupWatch()

task 'test', ->
  reporter = if process.env['LIST'] then 'spec' else 'dot'

  vendor ->
    build ->
      ssl_cert ->
        tokens ->
          test_cases = glob.sync 'test/js/**/*_test.js'
          test_cases.sort()  # Consistent test case order.
          run 'node node_modules/mocha/bin/mocha --colors --slow 200 ' +
              "--timeout 20000 --reporter #{reporter} " +
              '--require test/js/helpers/setup.js ' +
              '--globals Dropbox ' + test_cases.join(' ')

task 'fasttest', ->
  clean ->
    build ->
      ssl_cert ->
        fasttest (code) ->
          process.exit code

task 'webtest', ->
  vendor ->
    build ->
      ssl_cert ->
        tokens ->
          webtest()

task 'cert', ->
  fs.removeSync 'test/ssl' if fs.existsSync 'test/ssl'
  ssl_cert()

task 'vendor', ->
  fs.removeSync 'test/vendor' if fs.existsSync 'test/vendor'
  vendor()

task 'tokens', ->
  fs.removeSync './test/token' if fs.existsSync 'test/tokens'
  build ->
    ssl_cert ->
      tokens ->
        process.exit 0

task 'doc', ->
  fs.mkdirSync 'doc' unless fs.existsSync 'doc'
  run 'node_modules/codo/bin/codo'

task 'devdoc', ->
  fs.mkdirSync 'doc' unless fs.existsSync 'doc'
  run 'node_modules/codo/bin/codo --private'

task 'sitedoc', ->
  fs.mkdir 'sitedoc' unless fs.existsSync 'sitedoc'
  fs.mkdir 'sitedoc/yaml' unless fs.existsSync 'sitedoc/yaml'
  run 'node_modules/codo/bin/codo --theme yaml --output-dir sitedoc/yaml', ->
    siteDoc 'sitedoc'


task 'extension', ->
  run 'node node_modules/coffee-script/bin/coffee ' +
      '--compile test/chrome_extension/*.coffee'

task 'chrome', ->
  vendor ->
    build ->
      buildChromeApp 'app_v1'

task 'chrome2', ->
  vendor ->
    build ->
      buildChromeApp 'app_v2'

task 'chrometest', ->
  vendor ->
    build ->
      buildChromeApp 'app_v1', ->
        testChromeApp()

task 'chrometest2', ->
  vendor ->
    build ->
      buildChromeApp 'app_v2', ->
        testChromeApp()

task 'cordova', ->
  vendor ->
    build ->
      buildCordovaApp()

task 'cordovatest', ->
  vendor ->
    build ->
      buildCordovaApp ->
        testCordovaApp()

build = (callback) ->
  buildCode ->
    buildTests ->
      callback() if callback

buildCode = (callback) ->
  # Ignoring ".coffee" when sorting.
  # We want "auth_driver.coffee" to sort before "auth_driver/browser.coffee"
  source_files = glob.sync 'src/**/*.coffee'
  source_files.sort (a, b) ->
    a.replace(/\.coffee$/, '').localeCompare b.replace(/\.coffee$/, '')

  # TODO(pwnall): add --map after --compile when CoffeeScript #2779 is fixed
  #               and the .map file isn't useless
  command = 'node node_modules/coffee-script/bin/coffee --output lib ' +
      "--compile --join dropbox.js #{source_files.join(' ')}"

  run command, noExit: true, noOutput: true, (exitCode) ->
    if exitCode is 0
      callback() if callback
      return

    # The build failed.
    # Compile without --join for decent error messages.
    fs.mkdirSync 'tmp' unless fs.existsSync 'tmp'
    commands = []
    commands.push 'node node_modules/coffee-script/bin/coffee ' +
        '--output tmp --compile ' + source_files.join(' ')
    async.forEachSeries commands, run, ->
      # run should exit on its own. This is mostly for clarity.
      process.exit 1

buildTests = (callback) ->
  fs.mkdirSync 'test/js' unless fs.existsSync 'test/js'
  commands = []
  # Tests are supposed to be independent, so the build order doesn't matter.
  test_dirs = glob.sync 'test/src/**/'
  for test_dir in test_dirs
    out_dir = test_dir.replace(/^test\/src\//, 'test/js/')
    test_files = glob.sync path.join(test_dir, '*.coffee')
    commands.push "node node_modules/coffee-script/bin/coffee " +
                  "--output #{out_dir} --compile #{test_files.join(' ')}"
  async.forEachSeries commands, run, ->
    callback() if callback

clean = (callback) ->
  dirs = [
    'doc',
    'sitedoc/all.json',
    'sitedoc/html',
    'sitedoc/yaml',
    'test/js',
    'tmp'
  ]
  cleanDir = (dirName, callback) ->
    fs.exists dirName, (exists) ->
      unless exists
        callback() if callback
        return
      fs.remove dirName, (error) ->
        callback() if callback
  async.forEachSeries dirs, cleanDir, ->
    callback() if callback

buildPackage = (callback) ->
  # Minify the javascript, for browser distribution.
  commands = []
  commands.push 'cd lib && node ../node_modules/uglify-js/bin/uglifyjs ' +
      '--compress --mangle --output dropbox.min.js ' +
      '--source-map dropbox.min.map dropbox.js'
  async.forEachSeries commands, run, ->
    callback() if callback

setupWatch = (callback) ->
  scheduled = true
  buildNeeded = true
  cleanNeeded = true
  onTick = ->
    scheduled = false
    if cleanNeeded
      buildNeeded = false
      cleanNeeded = false
      console.log "Doing a clean build"
      clean -> build -> fasttest()
    else if buildNeeded
      buildNeed = false
      console.log "Building"
      build -> fasttest()
  process.nextTick onTick

  watchMonitor = (monitor) ->
    monitor.on 'created', (fileName) ->
      return unless path.basename(fileName)[0] is '.'
      buildNeeded = true
      unless scheduled
        scheduled = true
        process.nextTick onTick
    monitor.on 'changed', (fileName) ->
      return unless path.basename(fileName)[0] is '.'
      buildNeeded = true
      unless scheduled
        scheduled = true
        process.nextTick onTick
    monitor.on 'removed', (fileName) ->
      return unless path.basename(fileName)[0] is '.'
      cleanNeeded = true
      buildNeeded = true
      unless scheduled
        scheduled = true
        process.nextTick onTick

  watch.createMonitor 'src/', watchMonitor
  watch.createMonitor 'test/src/', watchMonitor

fasttest = (callback) ->
  test_cases = glob.sync 'test/js/fast/**/*_test.js'
  test_cases.sort()  # Consistent test case order.
  run 'node node_modules/mocha/bin/mocha --colors --slow 200 --timeout 1000 ' +
      '--require test/js/helpers/fast_setup.js --reporter min ' +
      test_cases.join(' '), noExit: true, (code) ->
        callback(code) if callback

webtest = (callback) ->
  webFileServer = require './test/js/helpers/web_file_server.js'
  if 'BROWSER' of process.env
    if process.env['BROWSER'] is 'false'
      url = webFileServer.testUrl()
      console.log "Please open the URL below in your browser:\n    #{url}"
    else
      webFileServer.openBrowser process.env['BROWSER']
  else
    webFileServer.openBrowser()
  callback() if callback?

ssl_cert = (callback) ->
  if fs.existsSync 'test/ssl/cert.pem'
    callback() if callback?
    return

  fs.mkdirSync 'test/ssl' unless fs.existsSync 'test/ssl'
  run 'openssl req -new -x509 -days 365 -nodes -batch ' +
      '-out test/ssl/cert.pem -keyout test/ssl/cert.pem ' +
      '-subj /O=dropbox.js/OU=Testing/CN=localhost ', callback

vendor = (callback) ->
  # All the files will be dumped here.
  fs.mkdirSync 'test/vendor' unless fs.existsSync 'test/vendor'

  # Embed the binary test image into a 7-bit ASCII JavaScript.
  buffer = fs.readFileSync 'test/binary/dropbox.png'
  bytes = (buffer.readUInt8(i) for i in [0...buffer.length])
  browserJs = "window.testImageBytes = [#{bytes.join(', ')}];\n"
  fs.writeFileSync 'test/vendor/favicon.browser.js', browserJs
  workerJs = "self.testImageBytes = [#{bytes.join(', ')}];\n"
  fs.writeFileSync 'test/vendor/favicon.worker.js', workerJs

  downloads = [
    # chai.js ships different builds for browsers vs node.js
    ['http://chaijs.com/chai.js', 'test/vendor/chai.js'],
    # sinon.js also ships special builds for browsers
    ['http://sinonjs.org/releases/sinon.js', 'test/vendor/sinon.js'],
    # ... and sinon.js ships an IE-only module
    ['http://sinonjs.org/releases/sinon-ie.js', 'test/vendor/sinon-ie.js']
  ]
  async.forEachSeries downloads, download, ->
    callback() if callback

testChromeApp = (callback) ->
  # Clean up the profile.
  fs.mkdirSync 'test/chrome_profile' unless fs.existsSync 'test/chrome_profile'

  # TODO(pwnall): remove experimental flag when the identity API gets stable
  command = "\"#{chromeCommand()}\" " +
      '--load-extension=test/chrome_app ' +
      # TODO(pwnall): figure out a way to get the app auto-loaded; the flag
      #               below is documented but doesn't work
      # '--app-id nibiohflpcgopggnnboelamnhcnnpinm ' +
      '--enable-experimental-extension-apis ' +
      '--user-data-dir=test/chrome_profile --no-default-browser-check ' +
      '--no-first-run --no-service-autorun --disable-default-apps ' +
      '--homepage=about:blank --v=-1 '

  run command, ->
    callback() if callback

buildChromeApp = (manifestFile, callback) ->
  buildStandaloneApp "test/chrome_app", ->
    run "cp test/chrome_app/manifests/#{manifestFile}.json " +
        'test/chrome_app/manifest.json', ->
          callback() if callback

buildStandaloneApp = (appPath, callback) ->
  unless fs.existsSync appPath
    fs.mkdirSync appPath
  unless fs.existsSync "#{appPath}/test"
    fs.mkdirSync "#{appPath}/test"
  unless fs.existsSync "#{appPath}/node_modules"
    fs.mkdirSync "#{appPath}/node_modules"

  links = [
    ['lib', "#{appPath}/lib"],
    ['node_modules/mocha', "#{appPath}/node_modules/mocha"],
    ['node_modules/sinon-chai', "#{appPath}/node_modules/sinon-chai"],
    ['test/token', "#{appPath}/test/token"],
    ['test/binary', "#{appPath}/test/binary"],
    ['test/html', "#{appPath}/test/html"],
    ['test/js', "#{appPath}/test/js"],
    ['test/vendor', "#{appPath}/test/vendor"],
  ]
  commands = for link in links
    "cp -r #{link[0]} #{path.dirname(link[1])}"
  async.forEachSeries commands, run, ->
    callback() if callback

chromeCommand = ->
  paths = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary',
    '/Applications/Chromium.app/MacOS/Contents/Chromium',
  ]
  for path in paths
    return path if fs.existsSync path

  if process.platform is 'win32'
    'chrome'
  else
    'google-chrome'

testCordovaApp = (callback) ->
  run 'test/cordova_app/cordova/run', ->
    callback() if callback

buildCordovaApp = (callback) ->
  if fs.existsSync 'test/cordova_app/www'  # iOS
    appPath = 'test/cordova_app/www'
  else if fs.existsSync 'test/cordova_app/assets/www'  # Android
    appPath = 'test/cordova_app/assets/www'
  else
    throw new Error 'Cordova www directory not found'

  buildStandaloneApp appPath, ->
    cordova_js = glob.sync("#{appPath}/cordova*.js").sort().
                      reverse()[0]
    run "cp #{cordova_js} #{appPath}/test/js/platform.js", ->
      run "cp test/html/cordova_index.html #{appPath}/index.html", ->
        callback() if callback

tokens = (callback) ->
  TokenStash = require './test/js/helpers/token_stash.js'
  tokenStash = new TokenStash tls: fs.readFileSync('test/ssl/cert.pem')
  tokenStash.get ->
    callback() if callback?

