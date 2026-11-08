FROM golang:1.21-bookworm as build

WORKDIR /app

COPY go.* ./
RUN go mod download

COPY . ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
      -ldflags='-w -s -extldflags "-static"' -a \
      -o /privacy-gateway-server

# The Beszel monitoring agent, fetched in its own stage so the runtime image
# gains no curl. The agent is a static musl binary, so it runs unchanged on
# this base. See docker/beszel-entrypoint.sh.
FROM ubuntu:26.04 AS beszel-agent
ARG BESZEL_AGENT_VERSION=0.21.1
# sha256 of beszel-agent_linux_amd64.tar.gz, from the release's own
# beszel_<version>_checksums.txt.
ARG BESZEL_AGENT_SHA256=3b6ee592632ec03b9a43312e99a40203a7b3d83fe40dd0c25acda1eb915ea7c0
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSLo /tmp/agent.tgz \
         "https://github.com/henrygd/beszel/releases/download/v${BESZEL_AGENT_VERSION}/beszel-agent_linux_amd64.tar.gz" \
    && echo "${BESZEL_AGENT_SHA256}  /tmp/agent.tgz" | sha256sum -c - \
    && tar -xzf /tmp/agent.tgz -C /usr/local/bin beszel-agent \
    && rm /tmp/agent.tgz

# ubuntu:26.04 rather than the previous distroless base: the fleet's other Fly
# apps run this base, and the Beszel wrapper entrypoint needs a shell, which
# distroless does not have. The gateway binary above is fully static, so it
# needs nothing from the base.
FROM ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c

ARG GIT_REVISION=unknown
LABEL revision ${GIT_REVISION}
COPY --from=build /privacy-gateway-server /privacy-gateway-server
COPY --from=beszel-agent /usr/local/bin/beszel-agent /usr/local/bin/beszel-agent
COPY docker/beszel-entrypoint.sh /usr/local/bin/beszel-entrypoint.sh
RUN chmod +x /usr/local/bin/beszel-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/beszel-entrypoint.sh"]
EXPOSE 8080

CMD ["/privacy-gateway-server"]
