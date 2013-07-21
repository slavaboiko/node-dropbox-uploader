
/**
 * Module dependencies.
 */

var express = require('express')
  , routes = require('./routes')
  , indrops = require('./routes/indrops')
  , http = require('http')
  , path = require('path');

// MongoDB settings:
var databaseUrl = "local";
var collections = ["users", "indrops"]

var app = express();
var db = require("mongojs").connect(databaseUrl, collections);

indrops.configure({
    db: db,
    dropbox_key: process.env.DROPBOX_APP_KEY,
    dropbox_secret: process.env.DROPBOX_APP_SECRET
});

// all environments
app.set('port', process.env.PORT || 3000);

app.base = process.env.CONTEXT_PATH || 'http://localhost:' + app.get('port');

app.set('views', __dirname + '/views');
app.set('view engine', 'jade');
app.use(express.favicon());
app.use(express.logger('dev'));
app.use(express.bodyParser());
app.use(express.cookieParser('F93dkLYhAn9eDsDgW3s'));
app.use(express.session({secret: 'vHEaZQr65pPCjd2'}));
app.use(express.methodOverride());
app.use(app.router);
app.use(require('stylus').middleware(__dirname + '/public'));
app.use('/assets', express.static(path.join(__dirname, 'public')));

// development only
app.configure('development', function(){
    app.use(express.errorHandler());
});

/**
 * Routes configuration
 */
app.all('*', indrops.auth_filter);
app.get('/', indrops.index);
app.post('/upload', indrops.upload);
app.get('/authorized', indrops.authorized);
app.get('/login', indrops.login);
app.get('/:userId', indrops.upload_page);

http.createServer(app).listen(app.get('port'), function(){
  console.log('Express server listening on port ' + app.get('port'));
});
