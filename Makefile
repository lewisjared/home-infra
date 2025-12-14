validate:
	bash scripts/validate.sh

watch:
	watch flux get kustomizations

ctx-staging:
	kubectl config use-context home-staging

ctx-prod:
	kubectl config use-context home-prod
