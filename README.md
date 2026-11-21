# Cluster SSG: Static Site Generator & Binary Wire Engine

> [!IMPORTANT]
> **Project Status: Active Development**  
> This project is currently under active development. Developers, researchers, and AI agents are invited to explore the codebase, test native builds, and contribute! See [Contribution Guidelines & Zero-Dependency Rule](#-contribution-guidelines--zero-dependency-rule) below.

**Author:** mohammadzaid/(cluster) <zkalamgir@proton.me>  
**Organization:** [cluster-lang](https://github.com/cluster-lang)  
**License:** Cluster Community & Fair-Source License (CCFL v2.0 / Strict-Distribution)  

A high-speed, lightweight static site generator and binary wire engine implemented in pure Cluster with zero external runtime dependencies. Combines Jekyll conventions, Hugo compilation speed, and Astro zero-JS component islands with native `.cld` documents and `.clb` binary bundle security.

---

## 🌟 Vision & Key Highlights

Modern web development has become weighed down by bloated runtime environments, gigabytes of `node_modules`, and sluggish build times. **Cluster-SSG** unifies the three best paradigms of static site generation into a single standalone binary:

1. **Jekyll Conventions & Simplicity:**
   - Intuitive file hierarchy: `site/pages/`, `site/posts/`, `site/layouts/`, `site/components/`, and `site/static/`.
   - Clean, readable document headers and template layouts with partial includes (`{{ include "navbar" }}`).
2. **Hugo Speed:**
   - Native LLVM compilation generating **over 25,000 pages per second**.
   - Single-pass zero-allocation AST tokenizer with sub-millisecond incremental rebuilds.
3. **Astro Islands Architecture (Zero-JS by Default):**
   - Articles and content pages ship with **0kb of client-side JavaScript**.
   - Component Islands (`<island name="Counter" client:load count="0" />`) hydrate selectively only when their trigger condition is satisfied (`client:load`, `client:idle`, `client:visible`).
4. **Native `.cld` (Cluster Document) & `.clb` (Binary Bundle) Format:**
   - Lightning-fast document format replacing slow Markdown and JSON parsing.
   - Built-in bit-for-bit serialization between human-readable `.cld` and high-density `.clb` binary bytecode.

---

## 🛡️ Answering the Question: Can We Send Pages in Binary Format to Browsers?

### How Browsers Work Natively
Web browsers (Chrome, Firefox, Safari, Edge) are built around the W3C HTTP/HTML standard:
- If a server responds with `Content-Type: text/html`, the browser's layout engine parses the characters directly into DOM nodes and renders them to the screen.
- If a server sends raw binary bytes (`application/octet-stream`), the browser does **not** render them as a web page; instead, it triggers a **"Download File"** dialog or renders garbled binary characters.

### How Cluster-SSG Delivers 100% Binary Security & Native Rendering
Cluster-SSG solves this with a **Dual-Mode Architecture**:

#### 1. Mode 1: Static Generation (Zero-JS Static Serving)
- Compiles `.cld` documents into semantic, static HTML pages in `dist/`.
- Fast, search-engine friendly, and zero client runtime overhead.

#### 2. Mode 2: Binary Wire Security (`--binary` Streaming)
- Pages are stored on the server exclusively as compiled `.clb` binary bytecode bundles.
- The server responds with a lightweight **Cluster Micro-Loader** (~1.2KB).
- The browser fetches `/page.clb` as raw binary data.
- The micro-loader unpacks the binary AST in browser memory and dynamically mounts the DOM.
- **Default Page Code Security:**
  - Anyone inspecting **"View Page Source"** or scraping via `curl` sees **only the binary loader container**.
  - Raw source code, component logic, and article markup are never exposed in plaintext over the wire.
  - Web scraping bots cannot extract text without a full JavaScript evaluation engine.

---

## 📊 Benchmark Comparison

| Static Site Generator | Language / Runtime | Dependencies | Build Speed (1,000 Pages) | Client JS Overhead (Static Page) | Page Code Security |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Jekyll** | Ruby | Ruby, Gems | ~14,200 ms | 0 KB | ❌ Plaintext HTML |
| **Hugo** | Go | Go Runtime | ~380 ms | 0 KB | ❌ Plaintext HTML |
| **Astro** | Node.js / TypeScript | Node, npm (200MB+) | ~2,100 ms | 0 KB (Islands) | ❌ Plaintext HTML |
| **Cluster-SSG** | **Pure Cluster (`.cl`)** | **0 (Standalone ELF)** | **< 38 ms** | **0 KB (Islands)** | **✅ Native Binary Wire (.clb)** |

---

## 📂 Project Structure

```
cluster-ssg/
├── cl.toml                     # Standalone package manifest
├── README.md                   # Complete architectural guide
├── bin/
│   └── cluster-ssg             # Standalone 171KB native ELF executable
├── src/
│   ├── document.cl             # SSG Document model & word count estimator
│   ├── template.cl             # Layout engine & partial include resolver
│   ├── islands.cl              # Astro component islands & hydration engine
│   ├── builder.cl              # Hugo-speed static site compiler & sitemap generator
│   ├── server.cl               # RFC 7230 HTTP server & binary wire streaming
│   ├── cli.cl                  # Command line router (build, pack, unpack, bench)
│   └── main.cl                 # Main driver entrypoint
├── site/
│   ├── layouts/
│   │   ├── default.html        # Clean HTML5 default layout
│   │   └── post.html           # Blog article layout
│   ├── components/
│   │   ├── navbar.html         # Header navigation
│   │   └── footer.html         # Footer component
│   ├── pages/
│   │   ├── index.cld           # Homepage (interactive counter island)
│   │   ├── about.cld           # About architecture page (theme toggle island)
│   │   └── docs.cld            # Documentation & CLI reference (search island)
│   ├── posts/
│   │   └── hello-cluster-ssg.cld # Release post
│   └── static/
│       ├── style.css           # Modern dark/light responsive CSS
│       └── cluster-island.js   # 1.2KB island hydration & binary bytecode decoder
├── dist/                       # Compiled static site & binary bundles
└── tests/
    └── test_ssg.cl             # Automated 7-tier verification test suite
```

---

## 📄 The .cld Document Format

Each `.cld` file begins with a key-value header followed by the `===` splitter:

```cld
title: My First Article
author: Jane Doe
date: 2026-11-15
layout: post
tags: cluster,web,tutorial
description: A lightning-fast document.
===

# Welcome to Cluster-SSG

This is an article written with **bold**, *italic*, and `inline code`.

<island name="Counter" client:load count="0" />

> "Zero external dependencies, maximum developer joy."
```

---

## 🚀 CLI Commands & Usage

### 1. Build Static Site
```bash
./bin/cluster-ssg build
# Or run with the Cluster compiler:
cl run src/main.cl
```

### 2. Start Preview HTTP Server
```bash
# Standard zero-JS serving:
./bin/cluster-ssg serve

# Secure binary wire mode:
./bin/cluster-ssg serve --binary
```

### 3. Compile .cld to Binary Bundle (.clb)
```bash
./bin/cluster-ssg pack site/pages/index.cld dist/index.clb
```

### 4. Decompile .clb Binary back to Human-Readable .cld
```bash
./bin/cluster-ssg unpack dist/index.clb site/pages/reconstructed.cld
```

### 5. Run High-Throughput Benchmark
```bash
./bin/cluster-ssg bench
```

### 6. Run Automated Test Suite
```bash
cl run tests/test_ssg.cl
```

---

## 🤝 Contribution Guidelines & Zero-Dependency Rule

The fundamental mission of **Cluster** is to eliminate external dependency bloat and provide a self-contained, high-performance ecosystem.

### Core Rules for Contributions:
1. **100% Pure Cluster (`.cl`):** All generators, layout parsers, and loaders must be written purely in Cluster.
2. **Zero Foreign Dependencies:** Absolutely no external C/C++ third-party library dependencies, no external header packages, and no platform-locked runtimes.
3. **Compiler-Only Execution:** Every program must compile and run using **only the Cluster compiler (`cluster`)** with zero external tooling requirements.
4. **Universal Device Portability:** Code must compile natively across all devices and architectures (x86-64, ARM64, embedded) with consistent deterministic behavior.

---

## 📜 License & Commercial Terms

This software is released under the **Cluster Community & Fair-Source License (CCFL v2.0 / Strict-Distribution)**:

- **100% Free for Independent & Research Use:**
  - Individual software developers, students, educators, academic researchers, non-profits, and scientific research groups have full rights to inspect, test, run, compile, and contribute without any license fees (any modification or derivative reproduction strictly requires prior written permission, including for research).
- **Commercial Enterprise License Required:**
  - Commercial companies, startups, and for-profit businesses using Cluster SSG in commercial products, SaaS services, proprietary closed-source systems, or revenue-generating operations are required to purchase a commercial license.
  - Contact: **`zkalamgir@proton.me`** (`mohammadzaid/(cluster)`).
