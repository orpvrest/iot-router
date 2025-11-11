foreground = yes
debug = 4
pid = /tmp/stunnel.pid
setuid = nobody
setgid = nobody
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

delay = yes
verifyChain = ${STUNNEL_VERIFY_CHAIN}
CAfile = ${STUNNEL_CA_FILE}
options = NO_SSLv2
options = NO_SSLv3
# TLSv1.0/1.1 disabled by default by upstream OpenSSL policies

[openvpn]
client = no
accept = ${STUNNEL_ACCEPT_HOST}:${STUNNEL_ACCEPT_PORT}
connect = ${STUNNEL_FORWARD_HOST}:${STUNNEL_FORWARD_PORT}
cert = ${STUNNEL_CERT_FILE}
key = ${STUNNEL_KEY_FILE}
