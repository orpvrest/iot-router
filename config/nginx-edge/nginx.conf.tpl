worker_processes auto;

events {
  worker_connections 1024;
}

stream {
  map $ssl_preread_server_name $stream_upstream {
    ${VPN_SNI_DOMAIN} stunnel:8443;
    default 127.0.0.1:4443;
  }

  server {
    listen 0.0.0.0:443 reuseport;
    proxy_pass $stream_upstream;
    ssl_preread on;
  }

  ${FORWARD_STREAMS}
}

http {
  limit_req_zone $binary_remote_addr zone=req_per_ip:10m rate=20r/s;
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;
  sendfile        on;
  keepalive_timeout  65;

  server {
    listen 80;
    server_name _;
    limit_req zone=req_per_ip burst=20 nodelay;

    location /.well-known/acme-challenge/ {
      root /var/www/certbot;
    }

    location /healthz {
      access_log off;
      return 200 'ok';
    }

    location / {
      return 301 https://$host$request_uri;
    }
  }

  server {
    listen 127.0.0.1:4443 ssl http2;
    server_name ${SITE_SNI_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${SITE_SNI_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${SITE_SNI_DOMAIN}/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;

    location / {
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_pass http://grafana:3000;
    }
  }
}
