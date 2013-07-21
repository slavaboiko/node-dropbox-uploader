# Subset of the node.js branch in test/src/helpers/setup.coffee

require('source-map-support').install()

exports = global

exports.Dropbox = require '../../../lib/dropbox'
exports.chai = require 'chai'
exports.sinon = require 'sinon'
exports.sinonChai = require 'sinon-chai'

webFileServer = require './web_file_server.js'
exports.testXhrServer = webFileServer.testOrigin()

# Shared setup.
exports.assert = exports.chai.assert
exports.expect = exports.chai.expect
