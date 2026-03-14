import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import '../shared/constants.dart';

class HttpServerService {
  late final shelf_io.IOServer server;
  final Function(String wasteType) onDetectionReceived;

  HttpServerService({required this.onDetectionReceived});

  Future<void> start() async {
    var pipeline = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_echoRequest);

    final srv = await shelf_io.serve(
        pipeline, AppConstants.httpServerHost, AppConstants.httpServerPort);
    
    // We cannot access srv.server directly because serve returns HttpServer, 
    // but IOServer doesn't exist as return type, it is dart:io HttpServer
    print('Serving at http://${srv.address.host}:${srv.port}');
  }

  Future<Response> _echoRequest(Request request) async {
    if (request.method == 'POST' && request.url.path == 'detect') {
      try {
        final bodyString = await request.readAsString();
        final jsonBody = jsonDecode(bodyString) as Map<String, dynamic>;
        
        if (jsonBody.containsKey('waste_type')) {
          final wasteType = jsonBody['waste_type'] as String;
          // Trigger the callback
          onDetectionReceived(wasteType);
          
          return Response.ok(
            jsonEncode({'status': 'received'}),
            headers: {'content-type': 'application/json'},
          );
        }
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Invalid request Format. Expected JSON with waste_type.'}),
        );
      }
    }
    return Response.notFound('Endpoint not found');
  }
}
