# NB面板 Docker镜像 - 基于 NodePassDash 3.4.0-beta3
# 端口: 4000 | 开源: https://github.com/lima-droid/NB-Panel

# ========= 前端构建阶段 =========
FROM node:22-alpine AS frontend-builder

RUN corepack enable && corepack prepare pnpm@latest --activate
ENV CI=true
ENV PNPM_HOME="/pnpm"
WORKDIR /app

COPY web/ ./web/

RUN cd web && \
    pnpm install --prod=false --ignore-scripts && \
    pnpm build

# ========= Go 构建阶段 =========
FROM golang:1.23-alpine AS backend-builder
ARG VERSION=dev
WORKDIR /app

RUN apk add --no-cache git gcc g++ make musl-dev sqlite-dev

COPY go.mod go.sum ./

ENV GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org

RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY --from=frontend-builder /app/cmd/server/dist ./cmd/server/dist

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

RUN go build -ldflags "-s -w -X main.Version=${VERSION}" -trimpath -o nbpanel ./cmd/server

# ========= 运行阶段 =========
FROM alpine:latest
ARG VERSION=dev
LABEL org.opencontainers.image.version=$VERSION
ENV APP_VERSION=$VERSION
WORKDIR /app

COPY --from=backend-builder /app/nbpanel ./

EXPOSE 4000
CMD ["/app/nbpanel"]
