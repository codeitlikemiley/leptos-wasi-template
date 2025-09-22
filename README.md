# 🦀 Leptos WASI Component Template

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Rust: 1.82+](https://img.shields.io/badge/Rust-1.82%2B-orange.svg)](https://www.rust-lang.org/)
[![Leptos](https://img.shields.io/badge/Leptos-SSR-purple.svg)](https://leptos.dev/)
[![WASI](https://img.shields.io/badge/WASI-Component-green.svg)](https://wasi.dev/)

A production-ready [cargo-generate](https://cargo-generate.github.io/cargo-generate/) template for creating full-stack Rust web applications using [Leptos](https://leptos.dev/) framework with WebAssembly System Interface (WASI) Components. This template provides a complete, working setup for server-side rendered (SSR) Rust web applications with client-side hydration, ready for deployment on any WASI-compatible runtime.

> **Note:**  
> The default branch/tag (`0.1.3`) is pinned to match a specific `leptos_wasi` version.  
> Using `main` or newer tags may introduce breaking changes unless you explicitly opt into them.

---

## 🚀 Quick Start

Install cargo-generate:

```bash
cargo install cargo-generate
````

Generate a new project using the stable release:

```bash
cargo generate --git https://github.com/codeitlikemiley/leptos-wasi-template --name my-app
```

Generate from a specific version:

```bash
cargo generate --git https://github.com/codeitlikemiley/leptos-wasi-template --branch 0.1.3 --name my-app
```

Generate from the development branch:

```bash
cargo generate --git https://github.com/codeitlikemiley/leptos-wasi-template --branch main --name my-app
```

---

## 🌟 Features

* **WASI Component Architecture** – Full Guest trait and WasiExecutor implementation
* **Server-Side Rendering (SSR)** – Fast initial page loads
* **Client-Side Hydration** – Interactive UI with seamless hydration
* **Server Functions** – Type-safe RPC between client and server
* **File-Based Routing** – Automatic routing for organized pages
* **Static Asset Serving** – Built-in support for WASI filesystems
* **Tailwind CSS Support** – Pre-configured and ready to use
* **Working Counter Example** – Demonstrates full client-server flow

---

## 📋 Prerequisites

* Rust 1.82+
* WASI Target:

  ```bash
  rustup target add wasm32-wasip2
  ```
* cargo-generate:

  ```bash
  cargo install cargo-generate
  ```
* cargo-leptos:

  ```bash
  cargo install cargo-leptos
  ```
* Wasmtime CLI:

  ```bash
  cargo install wasmtime-cli
  ```
* (Optional) Tailwind CSS:

  ```bash
  npm install -g tailwindcss
  ```

---

## 🛠️ Build and Run

```bash
cd my-app
cargo leptos build --release
chmod +x serve.sh
./serve.sh
```

Access your app at `http://localhost:8080`.

---

## 📁 Project Structure

```
my-app/
├── Cargo.toml
├── README.md
├── serve.sh
├── public/
│   └── favicon.ico
└── src/
    ├── main.rs
    ├── lib.rs
    ├── server.rs
    ├── routes.rs
    └── pages/
        ├── mod.rs
        └── home.rs
```

---

## 📄 License

This template is dual-licensed under MIT or Apache 2.0. Generated projects are free to adopt their own licensing.

---

## 🗂 Versioning

Each template tag corresponds to a specific `leptos_wasi` version to ensure compatibility.
Check the available versions:

```bash
git ls-remote --tags https://github.com/codeitlikemiley/leptos-wasi-template
```

