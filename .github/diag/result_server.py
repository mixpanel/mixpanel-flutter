import http.server, sys, os
root, out = sys.argv[1], sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=root, **k)
    def do_POST(s):
        n = int(s.headers['Content-Length']); open(os.path.join(out, 'result_' + (s.path.split('mode=')[-1] if 'mode=' in s.path else 'unknown') + '.json'), 'wb').write(s.rfile.read(n))
        s.send_response(204); s.end_headers()
http.server.HTTPServer(('127.0.0.1', 8765), H).serve_forever()
