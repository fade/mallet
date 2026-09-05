.PHONY: all help test test-unit test-cli bundle build install clean docker-build docker-publish

VERSION ?= latest
BINDIR ?= $(HOME)/.local/bin
IMAGE_NAME ?= fukamachi/mallet
LOCAL_IMAGE_NAME ?= mallet

all: build

help:
	@echo "Mallet Linter - Make targets:"
	@echo ""
	@echo "Build:"
	@echo "  make               - Build the mallet executable (default)"
	@echo "  make build         - Build the mallet executable"
	@echo "  make bundle        - Bundle dependencies for standalone distribution"
	@echo "  make install       - Build and publish mallet to $$BINDIR (default ~/.local/bin)"
	@echo ""
	@echo "Testing:"
	@echo "  make test          - Run all tests (unit + CLI integration)"
	@echo "  make test-unit     - Run unit tests only"
	@echo "  make test-cli      - Run CLI integration tests only"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build  - Build the mallet Docker image"
	@echo "  make docker-publish - Push the mallet Docker image"
	@echo ""
	@echo "Other:"
	@echo "  make clean         - Clean compilation cache"
	@echo "  make help          - Show this help message"
	@echo ""

test: test-unit test-cli

test-unit:
	@echo "Running unit tests..."
	@qlot exec sbcl --noinform --non-interactive \
		--eval "(when (find-package '#:qlot/local-init/setup) (setf (symbol-value (find-symbol \"*PROJECT-ROOT*\" '#:qlot/local-init/setup)) #p\"$(CURDIR)/\"))" \
		--eval '(asdf:load-system :mallet/tests)' \
		--eval '(or (rove:run :mallet/tests) (uiop:quit -1))'

test-cli:
	@echo ""
	@echo "Running CLI integration tests..."
	@./tests/cli-integration-test.sh
	@./tests/cli-exit-code-test.sh
	@./tests/cli-config-validation-errors-test.sh
	@./tests/cli-end-of-options-separator-test.sh
	@./tests/cli-format-fix-option-handling-test.sh
	@./tests/cli-src-zero-violations-test.sh
	@./tests/test-infrastructure-hygiene-test.sh

bundle:
	@qlot bundle --exclude mallet/tests

# The binary is deleted before dumping on purpose. ASDF treats an existing
# image as up to date when no source file has changed, so a rebuild after a
# commit would skip the dump and leave the previous commit's identity baked in.
# A binary that names a commit it was not built from is the defect --version
# exists to prevent, so correctness wins over the cost of always dumping.
build:
	@rm -f mallet
	@sbcl --noinform --non-interactive \
		--load init.lisp --eval "(asdf:make :mallet/executable)"

# Publish onto PATH atomically. Pre-commit hooks invoke this binary
# continuously, and copying over a running binary's inode can hand a process a
# half-written image. Writing beside the target and renaming means a reader sees
# either the old image or the new one, never a partial file.
install: build
	@mkdir -p "$(BINDIR)"
	@tmp="$(BINDIR)/.mallet.tmp.$$$$"; \
	 trap 'rm -f "$$tmp"' EXIT; \
	 cp mallet "$$tmp" && chmod 755 "$$tmp" && mv -f "$$tmp" "$(BINDIR)/mallet"
	@echo "installed $(BINDIR)/mallet"
	@"$(BINDIR)/mallet" --version

docker-build:
	docker build -t $(LOCAL_IMAGE_NAME):$(VERSION) .

docker-publish: docker-build
	docker tag $(LOCAL_IMAGE_NAME):$(VERSION) $(IMAGE_NAME):$(VERSION)
	docker push $(IMAGE_NAME):$(VERSION)

clean:
	@echo "Cleaning compilation cache and build artifacts..."
	@rm -f mallet
	@find . -name "*.fasl" -type f -delete
	@echo "Clean complete"
