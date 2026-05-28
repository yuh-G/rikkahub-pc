#  — Stage 1: Build —
# --platform=$BUILDPLATFORM ensures Bun runs natively (no QEMU emulation).
# Cross-compilation to TARGETARCH is handled via Bun's --target flag below.
FROM --platform=$BUILDPLATFORM docker.io/oven/bun:latest AS builder
ARG TARGETARCH

WORKDIR /build

# Install web-ui dependencies (cache layer)
COPY web-ui/package.json web-ui/bun.lock ./
RUN bun install

# Build web-ui SPA
COPY web-ui/ ./

# Bun's react-dom/server.bun.js lacks renderToPipeableStream needed by React Router's
# SSR build step. Symlink the Node.js server bundle in its place.
RUN rm -f node_modules/react-dom/server.bun.js \
    && ln -sf server.node.js node_modules/react-dom/server.bun.js \
    && rm -f node_modules/react-dom/cjs/react-dom-server.bun.development.js \
    && ln -sf react-dom-server.node.development.js node_modules/react-dom/cjs/react-dom-server.bun.development.js \
    && rm -f node_modules/react-dom/cjs/react-dom-server.bun.production.js \
    && ln -sf react-dom-server.node.production.js node_modules/react-dom/cjs/react-dom-server.bun.production.js

RUN bun run build

# Compile server — cross-compile to match the runtime platform
COPY pc-server/server.ts ./
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) BUN_TARGET=bun-linux-x64 ;; \
      arm64) BUN_TARGET=bun-linux-arm64 ;; \
      *) echo "Unsupported TARGETARCH: $TARGETARCH"; exit 1 ;; \
    esac; \
    bun build --compile --target="$BUN_TARGET" server.ts --outfile rikkahub-pc

#  — Stage 2: Runtime —
FROM gcr.io/distroless/base-debian12
WORKDIR /app

COPY --from=builder /build/rikkahub-pc ./
COPY --from=builder /build/build/client/ ./web-ui/build/client/

VOLUME ["/app/pc-data"]
EXPOSE 8080

ENTRYPOINT ["./rikkahub-pc", "--no-open"]
