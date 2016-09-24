import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:io';

void main() {
  HttpServer server = null;
  tearDown(() async {
    await server.close();
  });

  test("Logging after socket is closed does not throw exception", () async {
    var handler = (Request req) async {
      var socket = await req.innerRequest.response.detachSocket();
      socket.destroy();

      req.toDebugString(includeHeaders: true, includeBody: true, includeContentSize: true,
          includeElapsedTime: true, includeMethod: true, includeRequestIP: true, includeResource: true,
          includeStatusCode: true);

      return new Response.ok(null);
    };

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server.map((req) => new Request(req))
        .listen((req) async {
          var next = new RequestHandler();
          next.thenHandle(handler);

          await next.deliver(req);

          // We'll get here only if delivery succeeds, evne tho the response must be an error
          ensureExceptionIsCapturedByDeliver.complete(true);
        });

    try {
      await http.get("http://localhost:8000");
    } catch (e) {}

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test("Request handler that dies on bad state: header already sent is captured in RequestHandler", () async {
    var handler = (Request req) async {
      await req.response.close();

      return new Response.ok(null);
    };

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server
        .map((req) => new Request(req))
        .listen((req) async {
          var next = new RequestHandler();
          next.thenHandle(handler);
          await next.deliver(req);
          // We won't get here unless an exception is thrown, and that's what we're testing
          ensureExceptionIsCapturedByDeliver.complete(true);
        });

    await http.get("http://localhost:8000");

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test("Request handler throwing HttpResponseException that dies on bad state: header already sent is captured in RequestHandler", () async {
    var handler = (Request req) async {
      await req.response.close();

      throw new HTTPResponseException(400, "whocares");
      return new Response.ok(null);
    };

    var ensureExceptionIsCapturedByDeliver = new Completer();
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server
        .map((req) => new Request(req))
        .listen((req) async {
          var next = new RequestHandler();
          next.thenHandle(handler);
          await next.deliver(req);
          // We won't get here unless an exception is thrown, and that's what we're testing
          ensureExceptionIsCapturedByDeliver.complete(true);
        });

    await http.get("http://localhost:8000");

    expect(ensureExceptionIsCapturedByDeliver.future, completes);
  });

  test("Request handler maps QueryExceptions appropriately", () async {
    var handler = (Request req) async {
      var v = int.parse(req.innerRequest.uri.queryParameters["p"]);
      switch (v) {
        case 0: throw new QueryException(QueryExceptionEvent.internalFailure);
        case 1: throw new QueryException(QueryExceptionEvent.requestFailure);
        case 2: throw new QueryException(QueryExceptionEvent.conflict);
        case 3: throw new QueryException(QueryExceptionEvent.connectionFailure);
      }

      return new Response.ok(null);
    };
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8000);
    server
        .map((req) => new Request(req))
        .listen((req) async {
          var next = new RequestHandler();
          next.thenHandle(handler);
          await next.deliver(req);
        });

    var statusCodes = (await Future.wait(
          [0, 1, 2, 3].map((p) => http.get("http://localhost:8000/?p=$p"))))
        .map((resp) => resp.statusCode)
        .toList();
    expect(statusCodes, [500, 400, 409, 503]);
  });
}