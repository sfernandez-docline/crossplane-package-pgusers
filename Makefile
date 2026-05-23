# Build & push del Crossplane Configuration `crossplane-package-pgusers`.
#
# Pre-requisitos:
#   - crossplane CLI ≥ v1.18 (`crossplane --version`)
#   - GitHub PAT con `write:packages` scope, exportado como GITHUB_TOKEN
#
# Uso:
#   make test                      # render examples/* contra base/composition.yaml
#   make build VERSION=v0.1.0
#   make push  VERSION=v0.1.0
#   make all   VERSION=v0.1.0      # build + push

REGISTRY ?= ghcr.io/sfernandez-docline
NAME     ?= crossplane-package-pgusers
VERSION  ?= v0.1.0
IMG      := $(REGISTRY)/$(NAME):$(VERSION)
PKG_FILE := $(NAME)-$(VERSION).xpkg

.PHONY: build push login clean test all install-hooks
.DEFAULT_GOAL := build

# `crossplane render` simula la Composition contra cada example.
# examples/ usa `kind: Environment` (claim, lo que los usuarios escriben).
# `crossplane render` necesita el composite (`kind: XEnvironment`) — sed
# inline convierte sobre la marcha sin tocar el archivo.
#
# Composition emite Namespace + NetworkPolicy (siempre) + 0..3 XZone*Boostrap
# (depende de spec.bootstrap{Postgres,Mysql,Rabbitmq}) + 0..1 Schedule (Velero
# si type permite). Validamos ≥3 kinds: Namespace + NetworkPolicy + al menos
# 1 bootstrap o Velero.
test:
	@FAIL=0; for f in examples/*.yaml; do \
		echo "[test] render $$f"; \
		TMP=$$(mktemp --suffix=.yaml); \
		sed 's|^kind: Environment$$|kind: XEnvironment|' "$$f" > "$$TMP"; \
		OUT=$$(crossplane render "$$TMP" base/composition.yaml test/functions.yaml 2>&1); RC=$$?; \
		rm -f "$$TMP"; \
		if [ $$RC -ne 0 ]; then \
			echo "  FAIL: render error"; echo "$$OUT" | tail -10; FAIL=1; continue; \
		fi; \
		COUNT=$$(echo "$$OUT" | grep -c '^kind: '); \
		if [ "$$COUNT" -lt 3 ]; then \
			echo "  FAIL: expected ≥3 kinds, got $$COUNT"; \
			echo "$$OUT" | head -30; \
			FAIL=1; \
		else \
			echo "  OK: $$COUNT kinds rendered"; \
		fi; \
	done; \
	exit $$FAIL

build:
	@echo "[build] $(IMG) → $(PKG_FILE)"
	crossplane xpkg build \
		--package-root=. \
		--ignore="examples/*,test/*,workflows/*,docs/*,scripts/*,README.md,Makefile,*.xpkg,.gitignore,base/kustomization.yaml" \
		--package-file=$(PKG_FILE)

push: build
	@echo "[push] $(PKG_FILE) → $(IMG)"
	crossplane xpkg push --package-files=$(PKG_FILE) $(IMG)

login:
	@echo "$$GITHUB_TOKEN" | crossplane xpkg login ghcr.io --username=sfernandez-docline --password-stdin

clean:
	rm -f *.xpkg

all: test build push

install-hooks:
	@HOOKS_DIR="$$(git rev-parse --git-dir)/hooks"; \
	if [ ! -d "$$HOOKS_DIR" ]; then \
	  echo "ERROR: $$HOOKS_DIR no existe — ¿estás dentro de un repo git?"; \
	  exit 1; \
	fi; \
	cp scripts/pre-commit "$$HOOKS_DIR/pre-commit"; \
	chmod +x "$$HOOKS_DIR/pre-commit"; \
	echo "✓ pre-commit hook instalado en $$HOOKS_DIR/pre-commit"; \
	echo "  make test correrá al hacer commit en este package."
