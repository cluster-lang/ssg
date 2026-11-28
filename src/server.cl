// ==============================================================================
// Module:      Native Dev Server, Live Reload & Binary Wire Streamer (src/server.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-Python POSIX socket HTTP/1.1 server with smart static/clean
//              URL routing, MIME detection, .clb binary wire streaming, and live-reload.
// ==============================================================================

import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/config.cl"

model SsgServer:
    port: int
    dist_dir: string
    binary_wire_mode: int
    live_reload: int
    reload_token: string
    total_requests: int

fn ssg_server_new(port: int, dist_dir: string, binary_mode: int) -> SsgServer:
    return SsgServer(port, dist_dir, binary_mode, 0, "0", 0)

fn ssg_get_mime_type(path: string) -> string:
    ext := ssg_path_ext(path)
    if ext == ".html" or ext == ".htm": return "text/html; charset=utf-8"
    elif ext == ".css": return "text/css; charset=utf-8"
    elif ext == ".js" or ext == ".mjs": return "application/javascript; charset=utf-8"
    elif ext == ".wasm": return "application/wasm"
    elif ext == ".clb": return "application/octet-stream"
    elif ext == ".xml" or ext == ".rss" or ext == ".atom": return "application/xml; charset=utf-8"
    elif ext == ".json": return "application/json; charset=utf-8"
    elif ext == ".svg": return "image/svg+xml"
    elif ext == ".png": return "image/png"
    elif ext == ".jpg" or ext == ".jpeg": return "image/jpeg"
    elif ext == ".gif": return "image/gif"
    elif ext == ".webp": return "image/webp"
    elif ext == ".ico": return "image/x-icon"
    elif ext == ".woff2": return "font/woff2"
    elif ext == ".woff": return "font/woff"
    elif ext == ".txt": return "text/plain; charset=utf-8"
    return "application/octet-stream"

fn ssg_parse_request_path(raw_http: string) -> string:
    rlen := string_length(raw_http)
    if rlen < 4:
        return "/"
    sp1 := ssg_find_from(raw_http, " ", 0)
    if sp1 < 0:
        return "/"
    let mut sp2: int = ssg_find_from(raw_http, " ", sp1 + 1)
    if sp2 < 0:
        sp2 = rlen
    req_path := substring(raw_http, sp1 + 1, sp2 - sp1 - 1)
    q := ssg_find_from(req_path, "?", 0)
    if q >= 0:
        return substring(req_path, 0, q)
    return req_path

fn ssg_generate_binary_loader(page_clb_url: string) -> string:
    sb := sb_new_cap(1024)
    sb_append(sb, "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n")
    sb_append(sb, "  <meta charset=\"UTF-8\">\n")
    sb_append(sb, "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n")
    sb_append(sb, "  <title>Cluster Secure Binary Page</title>\n")
    sb_append(sb, "  <link rel=\"stylesheet\" href=\"/static/style.css\">\n")
    sb_append(sb, "  <script src=\"/static/cluster-island.js\"></script>\n")
    sb_append(sb, "</head>\n<body>\n")
    sb_append(sb, "  <div id=\"cluster-root\"><div style=\"padding:40px;text-align:center;font-family:sans-serif;\">")
    sb_append(sb, "<div style=\"font-size:22px;font-weight:bold;margin-bottom:8px;\">Streaming Cluster Binary Bundle...</div>")
    sb_append(sb, "<div style=\"color:#6b7280;font-size:14px;\">Zero-scraping binary wire mode active.</div></div></div>\n")
    sb_append(sb, "  <script>window.addEventListener('DOMContentLoaded',function(){if(window.ClusterSSG){ClusterSSG.loadBinary('" + ssg_escape_json(page_clb_url) + "','#cluster-root');}});</script>\n")
    sb_append(sb, "</body>\n</html>")
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn _srv_resolve_dist_file(dist_dir: string, req_path_raw: string) -> string:
    // Prevent directory traversal
    req_path := ssg_replace_all(req_path_raw, "..", "")
    if req_path == "/" or req_path == "":
        return ssg_path_join(dist_dir, "index.html")
    cand1 := ssg_path_join(dist_dir, req_path)
    if file_exists(cand1) == 1 and fs_is_dir(cand1) == 0:
        return cand1
    cand_idx := ssg_path_join(cand1, "index.html")
    if file_exists(cand_idx) == 1:
        return cand_idx
    cand_html := cand1 + ".html"
    if file_exists(cand_html) == 1:
        return cand_html
    return ""

fn ssg_handle_http(srv: SsgServer, raw_http: string) -> string:
    srv.total_requests = srv.total_requests + 1
    req_path := ssg_parse_request_path(raw_http)

    // Live-reload SSE & fallback polling endpoints used by dev watcher client
    if req_path == "/_cluster_sse":
        sse_body := "retry: 500\nevent: token\ndata: " + srv.reload_token + "\n\n"
        return "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\nX-Cluster-SSE: 1\r\nConnection: close\r\n\r\n" + sse_body

    if req_path == "/_cluster_reload":
        body := "{\"token\":\"" + srv.reload_token + "\"}"
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + str(string_length(body)) + "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" + body

    target_file := _srv_resolve_dist_file(srv.dist_dir, req_path)

    // Binary wire streaming mode check
    if srv.binary_wire_mode == 1 and string_length(target_file) > 0 and ssg_ends_with(target_file, ".html") == 1:
        let mut clb_url: string = req_path
        if clb_url == "/" or clb_url == "":
            clb_url = "/index.clb"
        elif ssg_ends_with(clb_url, "/") == 1:
            clb_url = clb_url + "index.clb"
        elif ssg_ends_with(clb_url, ".html") == 1:
            clb_url = substring(clb_url, 0, string_length(clb_url) - 5) + ".clb"
        else:
            clb_url = clb_url + ".clb"
        loader_html := ssg_generate_binary_loader(clb_url)
        return "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: " + str(string_length(loader_html)) + "\r\nX-Cluster-Security: Binary-Wire-Active\r\nConnection: close\r\n\r\n" + loader_html

    if string_length(target_file) > 0 and file_exists(target_file) == 1:
        let mut content: string = file_read(target_file)
        mime := ssg_get_mime_type(target_file)
        if srv.live_reload == 1 and ssg_ends_with(target_file, ".html") == 1 and ssg_contains(content, "</body>") == 1:
            lr_script := "<script>(function(){var tok='" + srv.reload_token + "';if('EventSource'in window){var es=new EventSource('/_cluster_sse');es.addEventListener('reload',function(){location.reload();});es.addEventListener('token',function(e){if(e.data&&e.data!==tok)location.reload();});}else{setInterval(function(){fetch('/_cluster_reload').then(function(r){return r.json();}).then(function(d){if(d.token&&d.token!==tok)location.reload();}).catch(function(){});},1000);}})();</script></body>"
            content = ssg_replace_all(content, "</body>", lr_script)
        return "HTTP/1.1 200 OK\r\nContent-Type: " + mime + "\r\nContent-Length: " + str(string_length(content)) + "\r\nX-Powered-By: Cluster-SSG/2.0\r\nConnection: close\r\n\r\n" + content

    not_found_body := "<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p><code>" + ssg_escape_html(req_path) + "</code> was not found.</p><a href=\"/\">Home</a></body></html>"
    return "HTTP/1.1 404 Not Found\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: " + str(string_length(not_found_body)) + "\r\nConnection: close\r\n\r\n" + not_found_body
