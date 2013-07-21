/**
 * User must supply dbox module to this route
 */
var db, helper,
    fs = require('fs'),
    dbox = require('../lib/dbox'),
    Hashids = require("hashids"),
    hashids = new Hashids("kt2qeZDKBkYAT3g", 5);


function _storeCredentials(client, res) {
    db.users.update({"uid": client.dropboxUid()}, {$set: {'credentials': client.credentials()}}, function(err, saved) {
        if( err || !saved ) console.log("User not saved");
        else console.log("User saved");
    });

    var cookie =  helper.getCookie(client);
    res.cookie(cookie.key, cookie.value, { signed: true, maxAge: 1000 * 2592000, path: '/' });
}

function _loadCredentials(req, callback) {
    helper.loadCookie(req.signedCookies, function(error, uid) {
        if (error) {
            return callback(error, null);
        }
        db.users.findOne({'uid': uid}, function(err, user){
            if ( err || !user ) {
                callback('User not found', null);
            } else {
                helper.client(user.credentials, callback);
            }
        });
    });
}

exports.configure = function(options) {
    db = options.db;

    helper = new dbox.Helper({
        key: options.dropbox_key,
        secret: options.dropbox_secret
    });
};

exports.auth_filter = function(req,res,next){
    _loadCredentials(req, function(error, client) {
        if (error || !client) {
            req.session.logged_in = false;
        } else {
            req.session.logged_in = true;
            req.session.client = client;
        }
        res.locals.session = req.session;
        next();
    });
};

/*
 * GET home page.
 */

exports.index = function(req, res){

    if (req.session.logged_in) {
        var uid = parseInt(req.session.client.dropboxUid());

        return res.render('home', {
            title: 'Home page',
            url: req.app.base + '/' + hashids.encrypt(uid)
        });
    }
    res.render('index', { title: 'Express' });
};

exports.upload_page = function (req, res) {
    var uidHash = req.params.userId;
    var uid = hashids.decrypt(uidHash)[0];

    db.users.findOne({'uid': ''+ uid}, function(err, user){
        if ( err || !user ) {
            res.status(404).render('error', {
                title: "Page not found",
                error: err
            });
        } else {
            res.render('upload', {
                title: 'Upload',
                userId: uidHash
            });
        }
    });
};

exports.upload = function (req, res) {
    var file = req.files.file;
    var uid = hashids.decrypt(req.body.uid)[0] + '';

    if (!file) {
        res.status(400).send('invalid file');
    } else {
        db.users.findOne({'uid': uid}, function(err, user){
            if ( err || !user ) {
                res.status(400).send('invalid user');
            } else {
                fs.readFile(file.path, function(err, data) {
                    if (err) {
                        res.send('error', 400);
                    } else {
                        res.send('success', 200);
                    }

                    helper.client(user.credentials).writeFile(file.name, data, function(status, reply) {
                        console.log('Status:', status);
                        console.log('Reply:', reply);
                    });
                });
            }
        });
    }
};

exports.login = function(req, res){
    if (req.session.logged_in) {
        return res.redirect(req.app.base);
    }

    helper.authenticate(req.app.base + '/authorized',
        function(authUrl, stateParam, client) {
            res.send("<script>window.location='"+authUrl+"';</script>");
        }
    );
}

exports.authorized = function(req, res){
    if (req.session.logged_in) {
        return res.redirect(req.app.base);
    }

    helper.authorize(req.query, function(error, client) {
        if (error) {
            console.log('Error: ', error);
            res.render("error", {
                error: error
            });
        } else {
            _storeCredentials(client, res);
            res.redirect(req.app.base);
        }
    });
}