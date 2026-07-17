# Local model resources

This directory intentionally contains no model or tokenizer payload. The lightweight app downloads
the exact files from Hugging Face, verifies them, and caches them on first use.

The large Core ML package is not bundled in the project. On first use, the app downloads the
individual files under:

- `coreml/SmolGPT-Fables-v1-CoreML-INT4.mlpackage/`

`coreml/coreml-checksums.sha256` lists every package and tokenizer file. The app downloads each
file without making a duplicate archive, verifies it, compiles the package, and caches `.mlmodelc`
in Application Support. Generation then
runs offline. The runtime requires `inputIds`, a `logits` output with vocabulary size 49,152, and
supports a stateful KV cache when the package exposes Core ML state.
