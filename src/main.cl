// ==============================================================================
// Cluster-SSG: Main Application Driver (src/main.cl)
// 100% Pure Cluster Language · Zero External Dependencies
// ==============================================================================

import "std/cld.cl"
import "src/document.cl"
import "src/template.cl"
import "src/islands.cl"
import "src/builder.cl"
import "src/server.cl"
import "src/cli.cl"

fn main() -> int:
    cli_print_banner()

    cfg := config_default()

    // 1. Run Complete Static Site Build
    println("\n--- Step 1: Building Static Site (Jekyll Conventions + Hugo Speed) ---")
    cli_run_build(cfg)

    // 2. Binary Packaging Demonstration (.cld -> .clb)
    println("\n--- Step 2: Binary Packaging & Security (.cld -> .clb) ---")
    cld_in := "site/pages/index.cld"
    clb_out := "dist/index_standalone.clb"
    cli_run_pack(cld_in, clb_out)

    // 3. Binary Unpacking (.clb -> .cld)
    println("\n--- Step 3: Binary Unpacking & Fidelity Verification (.clb -> .cld) ---")
    cld_reconstructed := "dist/reconstructed_index.cld"
    cli_run_unpack(clb_out, cld_reconstructed)
    assert(file_exists(cld_reconstructed) == 1)

    // 4. Built-in HTTP Server Demonstration (Standard Mode)
    println("\n--- Step 4: Built-in HTTP Server (Standard Mode) ---")
    srv_std := ssg_server_new(3000, "dist", 0)
    raw_req_std := "GET /index.html HTTP/1.1\r\nHost: localhost:3000\r\nUser-Agent: curl/7.88.1\r\n\r\n"
    res_std := ssg_handle_http(srv_std, raw_req_std)
    println("Request: GET /index.html")
    println("Response Status: " + substring(res_std, 0, 17))
    println("Response Headers (preview):\n" + substring(res_std, 0, 160) + "...\n")
    assert(substring(res_std, 9, 3) == "200")

    // 5. Binary Wire Streaming Server Mode (Zero-Scraping Default Page Security)
    println("--- Step 5: Binary Wire Streaming Mode (Anti-Scraping Security) ---")
    srv_bin := ssg_server_new(3000, "dist", 1)
    raw_req_bin := "GET /about.html HTTP/1.1\r\nHost: localhost:3000\r\nUser-Agent: curl/7.88.1\r\n\r\n"
    res_bin := ssg_handle_http(srv_bin, raw_req_bin)
    println("Request: GET /about.html (Secure Binary Mode)")
    println("Response Status: " + substring(res_bin, 0, 17))
    println("Response Preview (Micro-Loader Bytecode Container):\n" + substring(res_bin, 0, 220) + "...\n")
    assert(substring(res_bin, 9, 3) == "200")

    // 6. High-Throughput Hugo-Speed Benchmark
    println("--- Step 6: Hugo-Speed Benchmark (1,000 Pages In-Memory Compilation) ---")
    cli_run_bench()

    println("\n=================================================================")
    println("    ✓ Cluster-SSG successfully executed all pipelines!           ")
    println("=================================================================")
    return 0
