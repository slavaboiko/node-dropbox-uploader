describe 'Dropbox.Util.Xhr', ->
  beforeEach ->
    @node_js = module? and module?.exports? and require?
    @oauth = new Dropbox.Util.Oauth testKeys

  describe '#send', ->
    beforeEach ->
      @client = new Dropbox.Client testKeys
      @url = @client.urls.token

    it 'reports errors correctly', (done) ->
      url = @client.urls.token
      @xhr = new Dropbox.Util.Xhr 'POST', url
      @xhr.prepare().send (error, data) =>
        expect(data).to.equal undefined
        expect(error).to.be.instanceOf Dropbox.ApiError
        expect(error).to.have.property 'url'
        expect(error.url).to.equal url
        expect(error).to.have.property 'method'
        expect(error.method).to.equal 'POST'
        unless Dropbox.Util.Xhr.ieXdr  # IE's XDR doesn't do HTTP status codes.
          expect(error).to.have.property 'status'
          expect(error.status).to.equal Dropbox.ApiError.INVALID_PARAM
          expect(error).to.have.property 'responseText'
        expect(error.responseText).to.be.a 'string'
        unless Dropbox.Util.Xhr.ieXdr  # IE's XDR hides the HTTP body on error.
          expect(error).to.have.property 'response'
          expect(error.response).to.be.an 'object'
          expect(error.response).to.have.property 'error'
        expect(error.toString()).to.match /^Dropbox API error/
        expect(error.toString()).to.contain 'POST'
        expect(error.toString()).to.contain url
        done()

    it 'reports errors correctly when onError is set', (done) ->
      url = @client.urls.token
      @xhr = new Dropbox.Util.Xhr 'POST', url
      listenerError = null
      xhrCallbackCalled = false
      @xhr.onError = (error, callback) ->
        expect(listenerError).to.equal null
        expect(xhrCallbackCalled).to.equal false
        listenerError = error
        callback error
      @xhr.prepare().send (error, data) =>
        xhrCallbackCalled = true
        expect(data).to.equal undefined
        expect(error).to.be.instanceOf Dropbox.ApiError
        expect(error).to.have.property 'url'
        expect(error.url).to.equal url
        expect(error).to.have.property 'method'
        expect(error.method).to.equal 'POST'
        expect(listenerError).to.equal error
        done()

    it 'reports network errors correctly', (done) ->
      url = 'https://broken.to.causeanetworkerror.com/1/oauth/request_token'
      @xhr = new Dropbox.Util.Xhr 'POST', url
      @xhr.prepare().send (error, data) =>
        expect(data).to.equal undefined
        expect(error).to.be.instanceOf Dropbox.ApiError
        expect(error).to.have.property 'url'
        expect(error.url).to.equal url
        expect(error).to.have.property 'method'
        expect(error.method).to.equal 'POST'
        expect(error).to.have.property 'responseText'
        expect(error.responseText).to.equal '(no response)'
        unless Dropbox.Util.Xhr.ieXdr  # IE's XDR doesn't do HTTP status codes.
          expect(error).to.have.property 'status'
          expect(error.status).to.equal Dropbox.ApiError.NETWORK_ERROR
        done()

    it 'sends Authorize headers correctly', (done) ->
      return done() if Dropbox.Util.Xhr.ieXdr  # IE's XDR doesn't set headers.

      url = @client.urls.accountInfo
      xhr = new Dropbox.Util.Xhr 'GET', url
      xhr.addOauthHeader @oauth
      xhr.prepare().send (error, data) ->
        expect(error).to.equal null
        expect(data).to.have.property 'uid'
        expect(data.uid.toString()).to.equal testKeys.uid
        expect(data).to.have.property 'display_name'
        done()

    describe 'with a binary response', ->
      beforeEach ->
        testImageServerOn()
        @xhr = new Dropbox.Util.Xhr 'GET', testImageUrl

      afterEach ->
        testImageServerOff()

      describe 'with responseType b', ->
        beforeEach ->
          @xhr.setResponseType 'b'

        it 'retrieves a string where each character is a byte', (done) ->
          @xhr.prepare().send (error, data) ->
            expect(error).to.not.be.ok
            expect(data).to.be.a 'string'
            bytes = (data.charCodeAt i for i in [0...data.length])
            expect(bytes).to.deep.equal testImageBytes
            done()

      describe 'with responseType arraybuffer', ->
        beforeEach ->
          @xhr.setResponseType 'arraybuffer'

        it 'retrieves a well-formed ArrayBuffer', (done) ->
          # Skip this test on node.js and IE 9 and below
          return done() unless ArrayBuffer?

          @xhr.prepare().send (error, buffer) ->
            expect(error).to.not.be.ok
            expect(buffer).to.be.instanceOf ArrayBuffer
            view = new Uint8Array buffer
            bytes = (view[i] for i in [0...buffer.byteLength])
            expect(bytes).to.deep.equal testImageBytes
            done()

      describe 'with responseType blob', ->
        beforeEach ->
          @xhr.setResponseType 'blob'

        it 'retrieves a well-formed Blob', (done) ->
          # Skip this test on node.js and IE 9 and below
          return done() unless Blob?

          @xhr.prepare().send (error, blob) ->
            expect(error).to.not.be.ok
            expect(blob).to.be.instanceOf Blob
            onBufferAvailable = (buffer) ->
              view = new Uint8Array buffer
              bytes = (view[i] for i in [0...buffer.byteLength])
              expect(bytes).to.deep.equal testImageBytes
              done()
            if typeof FileReaderSync isnt 'undefined'
              # Firefox WebWorkers don't have FileReader.
              reader = new FileReaderSync
              buffer = reader.readAsArrayBuffer blob
              onBufferAvailable buffer
            else
              reader = new FileReader
              reader.onloadend = ->
                return unless reader.readyState == FileReader.DONE
                onBufferAvailable reader.result
              reader.readAsArrayBuffer blob

      describe 'with responseType buffer', ->
        beforeEach ->
          if Buffer?
            @xhr.setResponseType 'buffer'

        it 'retrieves a well-formed Buffer on node.js', (done) ->
          return done() unless Buffer?

          @xhr.prepare().send (error, buffer) ->
            expect(error).to.not.be.ok
            expect(buffer).to.be.instanceOf Buffer
            bytes = (buffer.readUInt8(i) for i in [0...buffer.length])
            expect(bytes).to.deep.equal testImageBytes
            done()
