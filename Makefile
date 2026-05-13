.PHONY: install

install:
	chmod +x .githooks/pre-push
	git config core.hooksPath .githooks
	@echo "Hook 安装完成: .githooks/pre-push"
