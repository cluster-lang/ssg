# Contributing to Cluster

Thank you for your interest in contributing to **Cluster** and its ecosystem! Cluster is built with a singular mission: **zero external runtime dependencies, 100% pure Cluster language implementation, ultra-fast compilation, and universal cross-platform portability**.

---

## 📜 Legal Stewardship & Contributor Agreement

> **Important License & Stewardship Notice:**  
> **By submitting a Pull Request, you agree that your contribution is 100% pure Cluster code and is licensed under the repository's CCFL v2.0 terms with copyright stewardship managed by Mohammad Zaid / cluster.**

---

## 🛡️ Core Rules for Contributions

Every contribution must strictly adhere to the following principles:

1. **100% Pure Cluster (`.cl`):**  
   All code, algorithms, data structures, and utilities must be written strictly in pure Cluster language (`.cl`). Absolutely NO C/C++ third-party library dependencies, no external header packages, no foreign language wrappers (Node.js, Python, Go, Rust), and no platform-locked runtimes.
2. **Compiler-Only Execution:**  
   Your code must compile and run using **only the official Cluster compiler (`cl`)** with zero external tooling requirements.
3. **Deterministic & Portable:**  
   Code must execute deterministically across all supported platforms (Linux, macOS, Windows, Android, iOS, embedded) on both x86-64 and ARM64.
4. **Clean Code & No Cache Artifacts:**  
   Never commit build outputs, cache directories (`.cl_cache/`), editor configs (`.vscode/`), or temporary logs.

---

## ✍️ Mandatory File Header & Contributor Attribution

We believe in giving credit to our contributors. To ensure your authorship is permanently recorded in the codebase and git history, **every contributed file MUST include the following comment header at the top**:

```cl
// ==============================================================================
// Module / File:  <filename or module_name>
// Description:    <Brief 1-2 sentence description of functionality>
// Author:         <Your Full Name> (<your_email@domain.com>)
// GitHub:         @<your_github_username>
// Stewardship:    Mohammad Zaid / Cluster Organization (https://github.com/cluster-lang)
// License:        CCFL v2.0 / Strict-Distribution
// ==============================================================================
```

---

## 🚀 Step-by-Step Contribution Workflow

### 1. Fork the Repository
Click the **Fork** button at the top right of this repository to create your personal copy on GitHub.

### 2. Clone Your Fork
```bash
git clone https://github.com/<your-username>/<repo-name>.git
cd <repo-name>
```

### 3. Create a Feature Branch
```bash
git checkout -b feature/my-new-contribution
```

### 4. Write & Test Your Code
Write your pure Cluster code and run local verification using the official Cluster compiler:
```bash
# Type-check and compile
cl check my_code.cl

# Run local test suite
cl run my_test.cl
```

### 5. Commit with Clean Messages
```bash
git add my_code.cl
git commit -m "feat: add <feature description>"
```

### 6. Push and Open a Pull Request
Push your branch to your GitHub fork:
```bash
git push origin feature/my-new-contribution
```
Then visit the official repository on GitHub and click **"Compare & pull request"**. Fill out the Pull Request template and submit!

---

## 🔍 Pull Request Review Process

1. **Automated Verification:** Automated checks will verify syntax, buildability, and ensure no foreign files or caches are introduced.
2. **Review & Guidance:** Mohammad Zaid (`@zk-mohammad`) and maintainers will review your submission line-by-line, test it, and provide constructive feedback if needed.
3. **Merge:** Once approved, your pull request will be merged into `main`, and your name will be permanently credited as an official contributor!
