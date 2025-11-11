COMPOSE ?= docker compose
ENV_FILE ?= .env

.PHONY: help up down logs build init-pki add-client dev-certs config-check status clean backup validate-env

help: ## Show available make targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*##"} {printf "  %-15s %s\n", $$1, $$2}'

up: ## Launch core stack services
	$(COMPOSE) --env-file $(ENV_FILE) up -d openvpn-core stunnel nginx-edge prometheus grafana node-exporter cadvisor openvpn-exporter

build: ## Build custom images
	$(COMPOSE) --env-file $(ENV_FILE) build --pull openvpn-core stunnel

down: ## Stop all services
	$(COMPOSE) --env-file $(ENV_FILE) down

logs: ## Tail logs from every container
	$(COMPOSE) --env-file $(ENV_FILE) logs -f

init-pki: ## Initialize PKI assets without starting the stack
	$(COMPOSE) --env-file $(ENV_FILE) run --rm --no-deps --entrypoint /opt/openvpn/scripts/bootstrap-pki.sh openvpn-core --only-pki

add-client: ## Issue a new client profile (CLIENT=name)
ifndef CLIENT
	$(error CLIENT variable required, e.g. make add-client CLIENT=alice)
endif
	$(COMPOSE) --env-file $(ENV_FILE) exec openvpn-core /opt/openvpn/scripts/build-client.sh $(CLIENT)

dev-certs: ## Mint self-signed certificates for local testing
	ENV_FILE=$(ENV_FILE) ./scripts/dev-selfsigned.sh

config-check: ## Render and validate docker-compose configuration
	$(COMPOSE) --env-file $(ENV_FILE) config

status: ## Show container status
	$(COMPOSE) --env-file $(ENV_FILE) ps

backup: ## Snapshot PKI, certbot data, and monitoring volumes into ./backups
	COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) ./scripts/backup.sh

validate-env: ## Ensure required env vars are present
	ENV_FILE=$(ENV_FILE) ./scripts/validate-env.sh

clean: ## Remove OpenVPN and certbot artifacts
	rm -rf data/openvpn/* data/certbot/live/* data/certbot/archive/*
