.PHONY: bootstrap-kind deploy forward down undeploy

bootstrap-kind:
	./scripts/bootstrap-kind.sh

deploy:
	./scripts/deploy.sh

forward:
	./scripts/port-forward.sh

down:
	./scripts/undeploy.sh

undeploy: down
