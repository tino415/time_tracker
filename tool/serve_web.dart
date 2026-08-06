// Serves a *built* web bundle, for `just web-smoke`.
//
// This is not required to develop against, and drift on the web does not need
// it: without COOP/COEP the page simply is not cross-origin isolated, so drift
// uses an OPFS implementation that does not want SharedArrayBuffer. That works
// fine — it is the arrangement gym_tracker runs on.
//
// It exists because the smoke test checks things only a *release-shaped* bundle
// has: the generated service worker, offline reload, and the hashed assets in
// build/web. `flutter run -d web-server` serves its own dev build and cannot
// serve build/web at all, and this toolchain's `flutter run` has no
// `--web-header` flag to add the isolation headers either. So: a small static
// server, which also lets the smoke test assert the isolated path rather than
// only the fallback.
//
//   dart tool/serve_web.dart [directory] [port]
//
// Defaults: build/web on 4242. Bind is 0.0.0.0 so a browser on the host can
// reach the VM.

import 'dart:io';

const _mimeTypes = <String, String>{
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.symbols': 'application/octet-stream',
};

Future<void> main(List<String> args) async {
  final root = Directory(args.isNotEmpty ? args[0] : 'build/web');
  final port = int.tryParse(args.length > 1 ? args[1] : '') ?? 4242;

  if (!root.existsSync()) {
    stderr.writeln('No such directory: ${root.path}\nRun `just web` first.');
    exit(1);
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('serving ${root.path} on http://0.0.0.0:$port (COOP/COEP on)');

  await for (final request in server) {
    try {
      await _handle(request, root);
    } catch (e) {
      stderr.writeln('${request.uri.path}: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The client may already be gone.
      }
    }
  }
}

Future<void> _handle(HttpRequest request, Directory root) async {
  final response = request.response;

  // Cross-origin isolation: the pair of headers that enables SharedArrayBuffer,
  // which drift's fastest OPFS implementation needs. Everything we serve is
  // same-origin, so require-corp costs nothing here.
  response.headers
    ..set('Cross-Origin-Opener-Policy', 'same-origin')
    ..set('Cross-Origin-Embedder-Policy', 'require-corp')
    ..set('Cross-Origin-Resource-Policy', 'same-origin');

  final path = Uri.decodeComponent(request.uri.path);
  var relative = path == '/' ? 'index.html' : path.replaceFirst('/', '');
  // Anything not on disk falls back to the shell, so a deep link still boots
  // the app rather than 404ing.
  var file = File('${root.path}/$relative');
  if (!file.existsSync() || FileSystemEntity.isDirectorySync(file.path)) {
    relative = 'index.html';
    file = File('${root.path}/index.html');
  }

  if (!file.existsSync()) {
    response.statusCode = HttpStatus.notFound;
    await response.close();
    return;
  }

  final dot = relative.lastIndexOf('.');
  final ext = dot < 0 ? '' : relative.substring(dot);
  response.headers.contentType = null;
  response.headers.set(
    HttpHeaders.contentTypeHeader,
    _mimeTypes[ext] ?? 'application/octet-stream',
  );

  // The shell and the service worker must never be served stale, or a rebuild
  // is invisible until the cache expires. Hashed assets can be cached hard, but
  // this is a dev/test server — keep it simple and revalidate everything else.
  response.headers.set(
    HttpHeaders.cacheControlHeader,
    (relative == 'index.html' || relative.contains('service_worker'))
        ? 'no-store'
        : 'no-cache',
  );

  await response.addStream(file.openRead());
  await response.close();
}
