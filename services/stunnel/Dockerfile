FROM alpine:3.19
RUN apk add --no-cache stunnel gettext bash
COPY entrypoint.sh /entrypoint.sh
COPY stunnel.conf.tpl /etc/stunnel/stunnel.conf.tpl
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
