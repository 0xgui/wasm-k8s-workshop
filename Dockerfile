FROM scratch
COPY target/wasm32-wasi/release/wasm-simple.wasm /simple.wasm
ENTRYPOINT [ "/simple.wasm" ]
