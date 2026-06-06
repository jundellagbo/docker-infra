FROM alpine:3.22

RUN apk add --no-cache dnsmasq

COPY dnsmasq.conf /etc/dnsmasq.conf

EXPOSE 53/udp
EXPOSE 53/tcp

CMD ["dnsmasq", "--keep-in-foreground", "--log-facility=-"]
