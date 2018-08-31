FROM crystallang/crystal:0.26.1 AS builder

RUN mkdir -p /app/_build
ADD . /app

WORKDIR /app

RUN shards install
RUN shards build http_request_gateway --production
RUN ldd bin/http_request_gateway | tr -s '[:blank:]' '\n' | grep '^/' | \
  xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'
RUN chmod +x /app/bin/http_request_gateway

FROM alpine:latest as certs
RUN apk --update add ca-certificates

# # runtime
FROM scratch
ENV SSL_CERT_PATH /etc/ssl/certs/ca-certificates.crt
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

COPY --from=builder /lib/x86_64-linux-gnu/libz.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libz.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libssl.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libcrypto.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libm.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libm-*.so /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libpthread.so.0 /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libpthread-*.so /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/librt.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/librt-*.so /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libdl.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libdl-*.so /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libgcc_s.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libc.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libc-*.so /lib/x86_64-linux-gnu/
COPY --from=builder /lib64/ld-linux-x86-64.so.* /lib64/
COPY --from=builder /lib/x86_64-linux-gnu/ld-*.so /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libnss_dns.so.* /lib/x86_64-linux-gnu/
COPY --from=builder /lib/x86_64-linux-gnu/libresolv.so.* /lib/x86_64-linux-gnu/

COPY --from=builder /app/deps /

COPY --from=builder /app/bin/http_request_gateway /http_request_gateway

ENV KEMAL_ENV production

ENV PORT 80
ENV REDIS_URL redis://localhost:6379/
ENTRYPOINT ["/http_request_gateway"]