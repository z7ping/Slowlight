# Build stage
FROM golang:1.23-alpine AS builder

ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG SLOWLIGHT_APP_VERSION=""
ARG SLOWLIGHT_GIT_HASH=""
ARG SLOWLIGHT_GIT_TIME=""
ARG SLOWLIGHT_BUILD_AT=""
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags="-X main.version=${SLOWLIGHT_APP_VERSION} -X main.commitHash=${SLOWLIGHT_GIT_HASH} -X main.commitTime=${SLOWLIGHT_GIT_TIME} -X main.buildTime=${SLOWLIGHT_BUILD_AT}" \
    -o slowlight-server ./cmd/

# Runtime stage
FROM alpine:3.20

RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/slowlight-server .

EXPOSE 8080
ENTRYPOINT ["./slowlight-server"]
