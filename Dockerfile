# NodePass WebUI - 整合SSE服务的Docker镜像
# Next.js应用内置SSE服务，单端口运行

# ========= 前端构建阶段 =========
FROM node:22-alpine AS frontend-builder

RUN corepack enable && corepack prepare pnpm@latest --activate
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
ENV CI=true

WORKDIR /app

# 先复制依赖文件，利用 Docker 缓存层
COPY web/package.json web/pnpm-lock.yaml ./web/
RUN cd web && \
    pnpm install --no-frozen-lockfile --prod=false --ignore-scripts

# 再复制源码构建
COPY web/ ./web/
RUN cd web && \
    pnpm build && \
    pnpm prune --prod

# ========= Go 构建阶段 =========
FROM golang:1.25-alpine AS backend-builder
ARG VERSION=dev
WORKDIR /app

RUN apk add --no-cache git gcc g++ make musl-dev sqlite-dev

COPY go.mod go.sum ./
ENV GOPROXY=https://goproxy.cn,https://goproxy.io,https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
ENV GOTIMEOUT=600s

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download || \
    (sleep 5 && go mod download) || \
    (sleep 10 && go mod download)

COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY --from=frontend-builder /app/cmd/server/dist ./cmd/server/dist

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"

RUN go build -ldflags "-s -w -X main.Version=${VERSION}" -o nb-panel ./cmd/server

# ========= 运行阶段 =========
FROM alpine:3.21
ARG VERSION=dev

LABEL org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.title=NB-Panel \
      org.opencontainers.image.description="NB-Panel - 隧道管理面板"

ENV APP_VERSION=$VERSION

RUN apk add --no-cache ca-certificates tzdata && \
    adduser -D -H -s /sbin/nologin nbpanel

WORKDIR /app
COPY --from=backend-builder /app/nb-panel ./

EXPOSE 4000

USER nbpanel
CMD ["/app/nb-panel"]
