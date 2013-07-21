(function() {
    var Dbox;

    Dbox = function() {
        return null;
    };

    Dbox.Helper = (function() {

        Helper.INVALID_COOKIE = 'Error :: Cookie not found';
        Helper.INVALID_TOKEN_ERROR = 'Error :: Invalid Token.';
        Helper.NOT_AUTHENTICATED_ERROR = 'Error :: Not authenticated';

        Helper.COOKIE_KEY = 'dropbox-auth_';

        Helper._salt = 'o5fHJTaGa';

        function Helper(options) {
            if (typeof options != "object") {
                throw new Error("Supply options to Dbox.Helper");
            }

            this._crypto = require('crypto');
            this._dropbox = require('dropbox');
            this._client = new this._dropbox.Client({
                key: options.key,
                secret: options.secret
            });
            this._responses = {};
            this._callbacks = {};
            this._cryptoSecret = options.secret + Dbox.Helper._salt;
            this._cookieKey = Dbox.Helper.COOKIE_KEY + this._client.appHash();
        }

        Helper.prototype.authorize = function(query, cb) {
            var stateParam = query.state,
                callback = this._callbacks[stateParam];

            if (callback) {
                this._responses[callback.client_id] = cb;
                callback.func(query);
                delete this._callbacks[stateParam];
            } else {
                cb(Dbox.Helper.INVALID_TOKEN_ERROR, null);
            }
        };

        Helper.prototype.client = function(credentials, callback) {
            var c = this._client;

            if (!callback) {
                callback = function(error, client) {
                    if (error || !client) {
                        c = null;
                    } else {
                        c = client;
                    }
                    return c;
                }
            }
            c.setCredentials(credentials);
            c.authenticate({interactive: false}, function(error, client) {
                if (client.isAuthenticated()) {
                    callback(null, client);
                } else {
                    if (!error)
                        error = Dbox.Helper.NOT_AUTHENTICATED_ERROR;
                    callback(error, client);
                }
                return client;
            });
            return c;
        };

        Helper.prototype.authenticate = function(redirectUri, callback) {
            var c = this._client;
            var _this = this;
            c.authDriver({
                url: function() { return redirectUri; },
                authType: function() { return "code" },
                doAuthorize: function(authUrl, stateParam, client, cb) {
                    _this._callbacks[stateParam] = {
                        client_id: client.oauth.id,
                        func: cb
                    };
                    callback(authUrl, stateParam, client);
                }
            });
            c.authenticate(function(error, client) {
                return _this._responses[client.oauth.id](error, client);
            });
        }

        Helper.prototype.getCookie = function(client) {
            return {
                key: this._cookieKey,
                value: this._encrypt(client.dropboxUid())
            };
        };

        Helper.prototype.loadCookie = function(cookies, callback) {
            var cookie = cookies[this._cookieKey];
            if (cookie) {
                callback(null, this._decrypt(cookie));
            } else {
                callback('Credentials weren\'t saved', null);
            }
        };

        Helper.prototype._encrypt = function(text){
            var cipher = this._crypto.createCipher('aes-256-cbc', this._cryptoSecret);
            var crypted = cipher.update(text,'utf8','hex');
            crypted += cipher.final('hex');
            return crypted;
        };

        Helper.prototype._decrypt = function(text){
            var decipher = this._crypto.createDecipher('aes-256-cbc', this._cryptoSecret);
            var dec = decipher.update(text,'hex','utf8');
            dec += decipher.final('utf8');
            return dec;
        };


    return Helper;

    })();

    module.exports = Dbox;

}).call(this);
