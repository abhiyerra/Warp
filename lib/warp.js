(function() {
  var PORT, Warp, WebSocketServer, fs, http, path, url,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  http = require('http');

  url = require('url');

  path = require('path');

  fs = require('fs');

  WebSocketServer = new require('websocket').server;

  PORT = 8898;

  module.exports = Warp = (function() {

    function Warp(options) {
      if (options == null) options = {};
      this.handleStdinEof = __bind(this.handleStdinEof, this);
      this.handleCommand = __bind(this.handleCommand, this);
      this.handleStdin = __bind(this.handleStdin, this);
      this.startStdinListener = __bind(this.startStdinListener, this);
      this.sendWebSocketMessage = __bind(this.sendWebSocketMessage, this);
      this.handleWebSocketMessage = __bind(this.handleWebSocketMessage, this);
      this.startWebSocketServer = __bind(this.startWebSocketServer, this);
      this.sendStaticFiles = __bind(this.sendStaticFiles, this);
      this.handleHttpRequest = __bind(this.handleHttpRequest, this);
      this.startHttpServer = __bind(this.startHttpServer, this);
      this.startServer = __bind(this.startServer, this);
      this.onSigint = __bind(this.onSigint, this);
      this.contentHtml = __bind(this.contentHtml, this);
      this.clientJs = __bind(this.clientJs, this);
      this.clientHtml = __bind(this.clientHtml, this);
      this.autoCloseClients = options.autoCloseClients;
      this.port = options.port || PORT;
      this.stdin = process.stdin;
      this.sockets = {};
      this.socketId = 0;
      this.buf = [];
      this.lastHtml = '';
      process.on('SIGINT', this.onSigint);
    }

    Warp.prototype.clientHtml = function() {
      return '<!DOCTYPE html>\n<html>\n  <head>\n    <title>Warp</title>\n    <style>\n      * { margin:0; padding:0 }\n      html {height:100%; overflow:hidden;}\n      header { display:none; height:1.2em; overflow:hidden; border-bottom:solid 1px #bbb; }\n      body { height:100%; width:100%; }\n      iframe#warp-frame { height:100%; width:100%; border:0; }\n      #closed-screen { display:none; height:100%; width:100%;\n                       text-align: center; font-size: 3em; color: #fff;\n                       position:absolute; left:0; top:0;\n                       background-color:rgba(0,0,0,0.8); z-index: 99999;\n                       padding: 2em;\n                      }\n    </style>\n    <script src="/client.js"></script>\n  </head>\n  <body>\n    <div id="closed-screen">Server not running :(</div>\n    <header>\n      Warp Client #<span id="client-id"/>\n    </header>\n    <iframe id="warp-frame" src="/content.html"/>\n  </body>\n</html>';
    };

    Warp.prototype.clientJs = function() {
      return "(function () {\n\nvar soc = new WebSocket('ws://' + location.host + '/', 'warp')\n, nop = function(){}\n, startupStack = []\n;\n\nstartupStack.push(function() {\n  var frame = document.getElementById('warp-frame')\n  , doc = frame.contentDocument\n  , scrollTo, point, inTop, inOffset, screen, docHeight\n  , top, screenDelta, scrollTo\n  ;\n\n  soc.onmessage = function(msg) {\n    msg = JSON.parse(msg.data);\n    console.log(msg.type, msg.data);\n    switch (msg.type) {\n      // case 'reload':\n      //   frame.contentWindow.location.reload();\n      //   break;\n      case 'load':\n      case 'url':\n        frame.contentWindow.location.href = msg.data;\n        break;\n      case 'html':\n        // // Remember Scroll Position\n        // scrollTo = doc.documentElement.scrollTop || doc.body.scrollTop;\n        doc.documentElement.innerHTML = msg.data;\n        document.title = frame.contentDocument.title;\n        // frame.contentWindow.scrollTo(0, scrollTo);\n        break;\n      case 'scroll':\n        point = msg.data.split(' ')\n        , inTop = parseInt(point[0], 10)\n        , inOffset = parseInt(point[1], 10)\n        , inScreen = parseInt(point[2], 10)\n        , docHeight = doc.documentElement.scrollHeight || doc.body.scrollHeight\n        , screen = doc.documentElement.clientHeight / docHeight * 100\n        , top = (doc.documentElement.scrollTop || doc.body.scrollTop) / docHeight * 100\n        , screenDelta = inScreen - screen\n        ;\n        scrollTo = (inTop * docHeight / 100)               // = Length to Window Top\n                   + (screenDelta >= 0 ? screenDelta : 0)  // Positive when browser screen is narrow than editor\n                   * docHeight / 100                       // = Hidden Screen Height\n                   * inOffset / 100;\n        frame.contentWindow.scrollTo(0, scrollTo);\n        break;\n      case 'client_id':\n        document.getElementById('client-id').innerText = msg.data;\n        break;\n      default:\n        soc.send(JSON.stringify({ type:'error', data:'unknown_type' }));\n    }\n  };\n\n  soc.send(JSON.stringify({ type:'status', data:'start' }));\n});\n\nstartupStack.push(nop);\nsoc.onopen = function() { startupStack.pop()(); };\n\nstartupStack.push(nop);\ndocument.addEventListener('DOMContentLoaded', function() { startupStack.pop()(); });\n\nstartupStack.pop()();\n\nsoc.onclose = function() {\n  if(" + this.autoCloseClients + ") { window.open('', '_self', ''); window.close(); }\n  document.getElementById('closed-screen').setAttribute('style', 'display:block;');\n};\n\n}());";
    };

    Warp.prototype.contentHtml = function() {
      return '<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml">\n  <head>\n    <meta charset="UTF-8"/>\n    <title></title>\n  </head>\n  <body>\n  </body>\n</html>';
    };

    Warp.prototype.onSigint = function() {
      if (this.httpServer) this.httpServer.close();
      return process.exit();
    };

    Warp.prototype.startServer = function() {
      this.startHttpServer();
      this.startWebSocketServer();
      return this.startStdinListener();
    };

    Warp.prototype.startHttpServer = function() {
      this.httpServer = http.createServer(this.handleHttpRequest);
      this.httpServer.listen(this.port);
      return console.log("start:lotalhost:" + this.port);
    };

    Warp.prototype.handleHttpRequest = function(req, res) {
      switch (url.parse(req.url).path) {
        case '/':
          res.writeHead(200, {
            'Content-Type': 'text/html'
          });
          res.write(this.clientHtml(), 'utf-8');
          return res.end();
        case '/content.html':
          res.writeHead(200, {
            'Content-Type': 'text/html'
          });
          res.write(this.contentHtml(), 'utf-8');
          return res.end();
        case '/client.js':
          res.writeHead(200, {
            'Content-Type': 'text/javascript'
          });
          res.write(this.clientJs(), 'utf-8');
          return res.end();
        default:
          return this.sendStaticFiles(req, res);
      }
    };

    Warp.prototype.sendStaticFiles = function(req, res) {
      var ext, p, _exists,
        _this = this;
      p = path.join(process.cwd(), url.parse(req.url).path);
      ext = path.extname(p);
      _exists = fs.exists || path.exists;
      return _exists(p, function(exists) {
        if (!exists) {
          res.writeHead(404, {
            'Content-Type': 'text/plain'
          });
          res.write('404 Not Found\n');
          res.end();
          return;
        }
        res.setHeader("Cache-Control", "max-age=100");
        return fs.readFile(p, 'binary', function(err, file) {
          if (err) {
            res.writeHead(500, {
              'Content-Type': 'text/plain'
            });
            res.write(err + "\n");
            res.end();
            return;
          }
          switch (ext.substr(1)) {
            case 'png':
              res.writeHead(200, {
                'Content-Type': 'image/png'
              });
              break;
            case 'gif':
              res.writeHead(200, {
                'Content-Type': 'image/gif'
              });
              break;
            case 'jpg' || 'jpeg':
              res.writeHead(200, {
                'Content-Type': 'image/jpeg'
              });
              break;
            case 'html' || 'htm':
              res.writeHead(200, {
                'Content-Type': 'text/html'
              });
              break;
            case 'js':
              res.writeHead(200, {
                'Content-Type': 'text/javascript'
              });
              break;
            case 'css':
              res.writeHead(200, {
                'Content-Type': 'text/css'
              });
              break;
            case 'swf':
            case 'swfl':
              res.writeHead(200, {
                'Content-Type': 'application/x-shockwave-flash'
              });
              break;
            default:
              res.writeHead(200, {
                'Content-Type': 'text/plain'
              });
          }
          res.write(file, 'binary');
          return res.end();
        });
      });
    };

    Warp.prototype.startWebSocketServer = function() {
      var _this = this;
      this.webSocketServer = new WebSocketServer({
        httpServer: this.httpServer
      });
      return this.webSocketServer.on('request', function(req) {
        var id, webSocket;
        webSocket = req.accept('warp', req.origin);
        id = _this.socketId++;
        webSocket.send(JSON.stringify({
          type: 'client_id',
          data: id
        }));
        _this.sockets[id] = webSocket;
        webSocket.on('message', function(msg) {
          msg = JSON.parse(msg.utf8Data);
          return _this.handleWebSocketMessage(msg, id);
        });
        return webSocket.on('close', function() {
          delete _this.sockets[id];
          return console.log("client_" + id + "_status:closed");
        });
      });
    };

    Warp.prototype.handleWebSocketMessage = function(msg, id) {
      console.log("client_" + id + "_" + msg.type + ":" + msg.data);
      if (msg.type === 'status') {
        if (msg.data === 'start') {
          return this.sendWebSocketMessage({
            type: 'html',
            data: this.lastHtml
          });
        }
      }
    };

    Warp.prototype.sendWebSocketMessage = function(msg, id) {
      var socket, _ref, _results;
      if (id) {
        return this.sockets[id].send(JSON.stringify(msg));
      } else {
        _ref = this.sockets;
        _results = [];
        for (id in _ref) {
          socket = _ref[id];
          _results.push(socket.send(JSON.stringify(msg)));
        }
        return _results;
      }
    };

    Warp.prototype.startStdinListener = function() {
      this.stdin.resume();
      this.stdin.setEncoding('utf8');
      this.stdin.on('data', this.handleStdin);
      return this.stdin.on('end', this.handleStdinEof);
    };

    Warp.prototype.handleStdin = function(chunk) {
      var char, _i, _len;
      for (_i = 0, _len = chunk.length; _i < _len; _i++) {
        char = chunk[_i];
        if (char === "\x00") {
          this.handleCommand(this.buf.join(''));
          this.buf = [];
        } else {
          this.buf.push(char);
        }
      }
      return false;
    };

    Warp.prototype.handleCommand = function(command) {
      var data, type;
      command = command.replace(/^\n+/, '');
      try {
        if (command[0] === "\x1B") {
          type = (command.match(/^\x1B(\S+)\x1D/))[1];
          data = (command.match(/\x1D([\w ]+)/))[1];
          return this.sendWebSocketMessage({
            type: type,
            data: data
          });
        } else {
          if (/\S+/.test(command)) {
            this.lastHtml = command;
            return this.sendWebSocketMessage({
              type: 'html',
              data: this.lastHtml
            });
          } else {
            return console.log("Blank HTML Data.");
          }
        }
      } catch (e) {
        return console.log(e);
      }
    };

    Warp.prototype.handleStdinEof = function() {};

    return Warp;

  })();

}).call(this);
