// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';

import 'src/channel.dart';
import 'src/exception.dart';
import 'src/sink_completer.dart';

/// A [WebSocketChannel] that communicates using a `dart:io` [WebSocket].
class IOWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  /// The underlying `dart:io` [WebSocket].
  ///
  /// If the channel was constructed with [IOWebSocketChannel.connect], this is
  /// `null` until the [WebSocket.connect] future completes.
  WebSocket _webSocket;

  @override
  String get protocol => _webSocket?.protocol;
  @override
  int get closeCode => _webSocket?.closeCode;
  @override
  String get closeReason => _webSocket?.closeReason;

  /// Future indicating if the connection has been established.
  /// It completes on successful connection to the websocket.
  Future get ready {
    return _readyCompleter?.future;
  }

  /// Completer for [ready].
  final Completer _readyCompleter;

  final Stream stream;
  @override
  final WebSocketSink sink;

  // TODO(nweiz): Add a compression parameter after the initial release.

  /// Creates a new WebSocket connection.
  ///
  /// Connects to [url] using [WebSocket.connect] and returns a channel that can
  /// be used to communicate over the resulting socket. The [url] may be either
  /// a [String] or a [Uri]. The [protocols] and [headers] parameters are the
  /// same as [WebSocket.connect].
  ///
  /// [pingInterval] controls the interval for sending ping signals. If a ping
  /// message is not answered by a pong message from the peer, the WebSocket is
  /// assumed disconnected and the connection is closed with a `goingAway` code.
  /// When a ping signal is sent, the pong message must be received within
  /// [pingInterval]. It defaults to `null`, indicating that ping messages are
  /// disabled.
  ///
  /// [timeout] determines how long the [WebSocket.connect] waits until it
  /// throws an error. It defaults to `null`, indicating that the connection
  /// will never throw an error caused by a server not responding.
  ///
  /// If there's an error connecting, the channel's stream emits a
  /// [WebSocketChannelException] wrapping that error and then closes.
  factory IOWebSocketChannel.connect(url,
      {Iterable<String> protocols,
      Map<String, dynamic> headers,
      Duration pingInterval,
      Duration timeout}) {
    var channel;
    var sinkCompleter = WebSocketSinkCompleter();
    var webSocketFuture = WebSocket.connect(url.toString(), headers: headers,protocols:protocols);
    if (timeout != null) {
      webSocketFuture = webSocketFuture.timeout(timeout);
    }

    var stream = StreamCompleter.fromFuture(webSocketFuture.then((webSocket) {
      webSocket.pingInterval = pingInterval;
      channel._webSocket = webSocket;
      channel._readyCompleter.complete(null);
      sinkCompleter.setDestinationSink(_IOWebSocketSink(webSocket));
      return webSocket;
    }).catchError((error) => throw WebSocketChannelException.from(error)));

    channel = IOWebSocketChannel._withoutSocket(stream, sinkCompleter.sink);
    return channel;
  }

  /// Creates a channel wrapping [socket].
  IOWebSocketChannel(WebSocket socket)
      : _webSocket = socket,
        stream = socket.handleError(
            (error) => throw WebSocketChannelException.from(error)),
        sink = _IOWebSocketSink(socket),
        _readyCompleter = Completer.sync();

  /// Creates a channel without a socket.
  ///
  /// This is used with [connect] to synchronously provide a channel that later
  /// has a socket added.
  IOWebSocketChannel._withoutSocket(Stream stream, this.sink)
      : _webSocket = null,
        stream = stream.handleError(
            (error) => throw WebSocketChannelException.from(error)),
        _readyCompleter = Completer.sync();
}

/// A [WebSocketSink] that forwards [close] calls to a `dart:io` [WebSocket].
class _IOWebSocketSink extends DelegatingStreamSink implements WebSocketSink {
  /// The underlying socket.
  final WebSocket _webSocket;

  _IOWebSocketSink(WebSocket webSocket)
      : _webSocket = webSocket,
        super(webSocket);

  @override
  Future close([int closeCode, String closeReason]) =>
      _webSocket.close(closeCode, closeReason);
}
