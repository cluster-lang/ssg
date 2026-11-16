// ==============================================================================
// Module:      Main Application Driver (main.cl)
// Project:     Cluster SSG (Static Site Generator & Binary Wire Engine)
// Author:      Zaid Alamgir (ZK Company)
// License:     MIT License
// Description: Application entrypoint, configuration loader, and build dispatcher.
// ==============================================================================

import "std/cld.cl"
import "src/document.cl"
import "src/template.cl"
import "src/islands.cl"
import "src/builder.cl"
import "src/server.cl"
import "src/cli.cl"

// ------------------------------------------------------------------------------
// Function: main
// Syntax:   fn main() -> int
// Purpose:  CLI entrypoint. Detects binary mode flag and executes static build pipeline.
// ------------------------------------------------------------------------------
fn main() -> int:
    cli_print_banner()

    let mut is_binary: int = 0
    if file_exists("site/.binary") == 1 or file_exists(".binary") == 1:
        is_binary = 1

    cfg := config_default()
    if is_binary == 1:
        cfg.output_binary = 1
        println("\n--- Building Static Site (Jekyll Conventions + Hugo Speed) ---")
        println("Binary Mode: ENABLED (Generating .clb binary bundles alongside .html)")
    else:
        cfg.output_binary = 0
        println("\n--- Building Static Site (Jekyll Conventions + Hugo Speed) ---")
        println("Binary Mode: DISABLED (Lean static site: clean .html, .css & .js only)")

    cli_run_build(cfg)
    return 0
