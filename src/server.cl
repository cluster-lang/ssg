// ==============================================================================
// Module:      Development Server & Binary Streamer (server.cl)
// Project:     Cluster SSG (Static Site Generator & Binary Wire Engine)
// Author:      Zaid Alamgir (ZK Company)
// License:     MIT License
// Description: Local HTTP server, live-reload listener, and secure binary wire stream handler.
// ==============================================================================

import "std/cld.cl"
import "src/document.cl"
import "src/builder.cl"

model SsgServer:
    port: int
    dist_dir: string
    binary_wire_mode: int
    total_requests: int

fn ssg_server_new(port: int, dist_dir: string, binary_mode: int) -> SsgServer:
    return SsgServer(port, dist_dir, binary_mode, 0)

fn ssg_get_mime_type(path: string) -> string:
    let plen: int = len(path)
    if plen > 5 and substring(path, plen - 5, 5) == ".html":
        return "text/html; charset=utf-8"
    elif plen > 4 and substring(path, plen - 4, 4) == ".css":
        return "text/css; charset=utf-8"
    elif plen > 3 and substring(path, plen - 3, 3) == ".js":
        return "application/javascript; charset=utf-8"
    elif plen > 4 and substring(path, plen - 4, 4) == ".clb":
        return "application/octet-stream"
    elif plen > 4 and substring(path, plen - 4, 4) == ".xml":
        return "application/xml; charset=utf-8"
    elif plen > 5 and substring(path, plen - 5, 5) == ".json":
        return "application/json; charset=utf-8"
    return "text/plain; charset=utf-8"

// Parse raw HTTP request line and extract method & path
fn ssg_parse_request_path(raw_http: string) -> string:
    let rlen: int = len(raw_http)
    if rlen < 4:
        return "/"
    
    // Find first space (after GET/POST)
    let mut sp1: int = -1
    let mut i: int = 0
    while i < rlen:
        if char_at(raw_http, i) == " ":
            sp1 = i
            break
        i = i + 1
    
    if sp1 < 0:
        return "/"
    
    // Find second space (before HTTP/1.1)
    let mut sp2: int = -1
    let mut j: int = sp1 + 1
    while j < rlen:
        if char_at(raw_http, j) == " ":
            sp2 = j
            break
        j = j + 1
    
    if sp2 < 0:
        sp2 = rlen
    
    req_path := substring(raw_http, sp1 + 1, sp2 - sp1 - 1)
    // Strip query string if present
    let mut qp: int = 0
    while qp < len(req_path):
        if char_at(req_path, qp) == "?":
            return substring(req_path, 0, qp)
        qp = qp + 1
    return req_path

// Generates the Cluster Micro-Loader HTML container for binary wire streaming
fn ssg_generate_binary_loader(page_clb_url: string) -> string:
    let mut h: string = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
    h = h + "  <meta charset=\"UTF-8\">\n"
    h = h + "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
    h = h + "  <title>Cluster Secure Binary Page</title>\n"
    h = h + "  <link rel=\"stylesheet\" href=\"/static/style.css\">\n"
    h = h + "  <script src=\"/static/cluster-island.js\"></script>\n"
    h = h + "</head>\n<body>\n"
    h = h + "  <div id=\"cluster-root\">\n"
    h = h + "    <div style=\"padding:40px;text-align:center;font-family:sans-serif;\">\n"
    h = h + "      <div style=\"font-size:24px;font-weight:bold;margin-bottom:12px;\">⚡ Streaming Cluster Binary Bundle...</div>\n"
    h = h + "      <div style=\"color:#6b7280;font-size:14px;\">Zero-scraping default page security active.</div>\n"
    h = h + "    </div>\n"
    h = h + "  </div>\n"
    h = h + "  <script>\n"
    h = h + "    window.addEventListener('DOMContentLoaded', function() {\n"
    h = h + "      ClusterSSG.loadBinary('" + page_clb_url + "', '#cluster-root');\n"
    h = h + "    });\n"
    h = h + "  </script>\n"
    h = h + "</body>\n</html>"
    return h

// Process an incoming HTTP request and return standard HTTP response wire string
fn ssg_handle_http(srv: SsgServer, raw_http: string) -> string:
    srv.total_requests = srv.total_requests + 1
    req_path := ssg_parse_request_path(raw_http)
    
    let mut target_file: string = srv.dist_dir + req_path
    if req_path == "/" or req_path == "":
        target_file = srv.dist_dir + "/index.html"
    elif req_path == "/about":
        target_file = srv.dist_dir + "/about.html"
    elif req_path == "/docs":
        target_file = srv.dist_dir + "/docs.html"

    // Binary wire streaming mode check
    if srv.binary_wire_mode == 1:
        // If requesting an HTML page, serve the secure binary loader pointing to .clb
        if cld_starts_with(target_file, srv.dist_dir + "/") == 1 and len(target_file) > 5 and substring(target_file, len(target_file) - 5, 5) == ".html":
            clb_url := req_path
            if clb_url == "/" or clb_url == "":
                clb_url = "/index.clb"
            elif len(clb_url) > 5 and substring(clb_url, len(clb_url) - 5, 5) == ".html":
                clb_url = substring(clb_url, 0, len(clb_url) - 5) + ".clb"
            else:
                clb_url = clb_url + ".clb"
            
            loader_html := ssg_generate_binary_loader(clb_url)
            let mut res: string = "HTTP/1.1 200 OK\r\n"
            res = res + "Content-Type: text/html; charset=utf-8\r\n"
            res = res + "Content-Length: " + str(len(loader_html)) + "\r\n"
            res = res + "X-Cluster-Security: Binary-Wire-Active\r\n"
            res = res + "Connection: close\r\n\r\n"
            res = res + loader_html
            return res

    // Normal static file resolution
    if file_exists(target_file) == 1:
        content := file_read(target_file)
        mime := ssg_get_mime_type(target_file)
        let mut res: string = "HTTP/1.1 200 OK\r\n"
        res = res + "Content-Type: " + mime + "\r\n"
        res = res + "Content-Length: " + str(len(content)) + "\r\n"
        res = res + "X-Powered-By: Cluster-SSG-v1.0\r\n"
        res = res + "Connection: close\r\n\r\n"
        res = res + content
        return res

    // 404 Not Found
    not_found_body := "<!DOCTYPE html><html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1><p>The requested URL " + req_path + " was not found on this Cluster SSG server.</p></body></html>"
    let mut res404: string = "HTTP/1.1 404 Not Found\r\n"
    res404 = res404 + "Content-Type: text/html; charset=utf-8\r\n"
    res404 = res404 + "Content-Length: " + str(len(not_found_body)) + "\r\n"
    res404 = res404 + "Connection: close\r\n\r\n"
    res404 = res404 + not_found_body
    return res404
