FROM scratch
COPY target/wasm32-wasi/release/wasm-test.wasm /test.wasm
ENTRYPOINT [ "/test.wasm" ]
