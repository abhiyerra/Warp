#!/usr/bin/env coffee

http = require 'http'
url = require 'url'
path = require 'path'
fs = require 'fs'
WebSocketServer = new require('websocket').server

PORT = 8898

module.exports = class Warp
  constructor: (options = {}) ->
    @autoCloseClients = options.autoCloseClients
    @port   = options.port   or PORT
    @stdin  = process.stdin
    @sockets = {}
    @socketId = 0
    @buf = []
    @lastHtml = ''
    process.on 'SIGINT', @onSigint

  # Static
  clientHtml: () => '''
<!DOCTYPE html>
<html>
  <head>
    <title>Warp</title>
    <style>
      * { margin:0; padding:0 }
      html {height:100%; overflow:hidden;}
      header { display:none; height:1.2em; overflow:hidden; border-bottom:solid 1px #bbb; }
      body { height:100%; width:100%; }
      iframe#warp-frame { height:100%; width:100%; border:0; }
      #closed-screen { display:none; height:100%; width:100%;
                       text-align: center; font-size: 3em; color: #fff;
                       position:absolute; left:0; top:0;
                       background-color:rgba(0,0,0,0.8); z-index: 99999;
                       padding: 2em;
                      }
    </style>
    <script src="/client.js"></script>
  </head>
  <body>
    <div id="closed-screen">Server not running :(</div>
    <header>
      Warp Client #<span id="client-id"/>
    </header>
    <iframe id="warp-frame" src="/content.html"/>
  </body>
</html>
'''

  clientJs: () => """
(function () {

var soc = new WebSocket('ws://' + location.host + '/', 'warp')
, nop = function(){}
, startupStack = []
;

startupStack.push(function() {
  soc.send(JSON.stringify({ type:'status', data:'start' }));

  var frame = document.getElementById('warp-frame')
  , doc = frame.contentDocument
  , scrollTo, point, inTop, inOffset, screen, docHeight
  , top, screenDelta, scrollTo
  ;

  soc.onmessage = function(msg) {
    msg = JSON.parse(msg.data);
    console.log(msg.type, msg.data);
    switch (msg.type) {
      // case 'reload':
      //   frame.contentWindow.location.reload();
      //   break;
      case 'load':
      case 'url':
        frame.contentWindow.location.href = msg.data;
        break;
      case 'html':
        // // Remember Scroll Position
        // scrollTo = doc.documentElement.scrollTop || doc.body.scrollTop;
        doc.documentElement.innerHTML = msg.data;
        document.title = frame.contentDocument.title;
        // frame.contentWindow.scrollTo(0, scrollTo);
        break;
      case 'scroll':
        point = msg.data.split(' ')
        , inTop = parseInt(point[0], 10)
        , inOffset = parseInt(point[1], 10)
        , inScreen = parseInt(point[2], 10)
        , docHeight = doc.documentElement.scrollHeight || doc.body.scrollHeight
        , screen = doc.documentElement.clientHeight / docHeight * 100
        , top = (doc.documentElement.scrollTop || doc.body.scrollTop) / docHeight * 100
        , screenDelta = inScreen - screen
        ;
        scrollTo = (inTop * docHeight / 100)               // = Length to Window Top
                   + (screenDelta >= 0 ? screenDelta : 0)  // Positive when browser screen is narrow than editor
                   * docHeight / 100                       // = Hidden Screen Height
                   * inOffset / 100;
        frame.contentWindow.scrollTo(0, scrollTo);
        break;
      case 'client_id':
        document.getElementById('client-id').innerText = msg.data;
        break;
      default:
        soc.send(JSON.stringify({ type:'error', data:'unknown_type' }));
    }
  };

});

startupStack.push(nop);
soc.onopen = function() { startupStack.pop()(); };

startupStack.push(nop);
document.addEventListener('DOMContentLoaded', function() { startupStack.pop()(); });

startupStack.pop()();

soc.onclose = function() {
  if(#{@autoCloseClients}) { window.open('', '_self', ''); window.close(); }
  document.getElementById('closed-screen').setAttribute('style', 'display:block;');
};

}());
"""

  contentHtml: () => '''
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <meta charset="UTF-8"/>
    <title></title>
  </head>
  <body>
  </body>
</html>
'''

  onSigint: () =>
    @httpServer.close() if @httpServer
    process.exit()

  startServer: () =>
    @startHttpServer()
    @startWebSocketServer()
    @startStdinListener()

  startHttpServer: () =>
    @httpServer = http.createServer @handleHttpRequest
    @httpServer.listen @port
    console.log "start:lotalhost:#{@port}"

  handleHttpRequest: (req, res) =>
    switch url.parse(req.url).path
      when '/'
        res.writeHead 200, 'Content-Type': 'text/html'
        res.write @clientHtml(), 'utf-8'
        res.end()
      when '/content.html'
        res.writeHead 200, 'Content-Type': 'text/html'
        res.write @contentHtml(), 'utf-8'
        res.end()
      when '/client.js'
        res.writeHead 200, 'Content-Type': 'text/javascript'
        res.write @clientJs(), 'utf-8'
        res.end()
      else
        @sendStaticFiles req, res

  sendStaticFiles: (req, res) =>
    p = path.join process.cwd(), url.parse(req.url).path
    ext = path.extname p

    _exists = fs.exists or path.exists

    _exists p, (exists) =>
      unless exists
        res.writeHead 404, 'Content-Type': 'text/plain'
        res.write '404 Not Found\n'
        res.end()
        return

      # Supress Chutternig Display
      res.setHeader "Cache-Control", "max-age=100"

      fs.readFile p, 'binary', (err, file) =>
        if err
          res.writeHead 500, 'Content-Type': 'text/plain'
          res.write err + "\n"
          res.end()
          return

        switch ext.substr 1
          when 'png'
            res.writeHead 200, 'Content-Type': 'image/png'
          when 'gif'
            res.writeHead 200, 'Content-Type': 'image/gif'
          when 'jpg' or 'jpeg'
            res.writeHead 200, 'Content-Type': 'image/jpeg'
          when 'html' or 'htm'
            res.writeHead 200, 'Content-Type': 'text/html'
          when 'js'
            res.writeHead 200, 'Content-Type': 'text/javascript'
          when 'css'
            res.writeHead 200, 'Content-Type': 'text/css'
          when 'swf', 'swfl'
            res.writeHead 200, 'Content-Type': 'application/x-shockwave-flash'
          else
            res.writeHead 200, 'Content-Type': 'text/plain'

        res.write file, 'binary'
        res.end()

  # WebSocket
  startWebSocketServer: () =>
    @webSocketServer = new WebSocketServer
      httpServer: @httpServer

    @webSocketServer.on 'request', (req) =>
      webSocket = req.accept 'warp', req.origin

      # Make internal reference for client id
      id = @socketId++

      webSocket.send JSON.stringify
        type: 'client_id'
        data: id

      @sockets[id] = webSocket

      #From Client
      webSocket.on 'message', (msg) =>
        msg = JSON.parse(msg.utf8Data);
        @handleWebSocketMessage msg, id

      webSocket.on 'close', () =>
        delete @sockets[id]
        console.log "client_#{id}_status:closed"

  handleWebSocketMessage: (msg, id) =>
    console.log "client_#{id}_#{msg.type}:#{msg.data}"
    if msg.type is 'status'
      if msg.data is 'start'
        @sendWebSocketMessage type: 'html', data: @lastHtml

  sendWebSocketMessage: (msg, id) =>
    if id
      @sockets[id].send (JSON.stringify msg)
    else
      for id, socket of @sockets
        socket.send (JSON.stringify msg)

  # STDIN
  startStdinListener: () =>
    @stdin.resume()
    @stdin.setEncoding 'utf8'
    @stdin.on 'data', @handleStdin
    @stdin.on 'end', @handleStdinEof

  handleStdin: (chunk) =>
    for char in chunk
      if char is "\x00" # Separate Command On Null
        @handleCommand @buf.join('')
        @buf = []
      else
        @buf.push(char)

    false

  handleCommand: (command) =>
    #console.log command
    command = command.replace /^\n+/, '' # normalize
    try
      if command[0] is "\x1B" # special command
        type = (command.match /^\x1B(\S+)\x1D/)[1]
        data = (command.match /\x1D([\w ]+)/)[1]
        @sendWebSocketMessage type: type, data: data
      else # html command
        if /\S+/.test command
          @lastHtml = command
          @sendWebSocketMessage type: 'html', data: @lastHtml
        else
          console.log "Blank HTML Data."
    catch e
      console.log e

  handleStdinEof: () =>
