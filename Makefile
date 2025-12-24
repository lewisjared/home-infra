validate:
	bash scripts/validate.sh

watch:
	watch flux get kustomizations

ctx-prod:
	kubectl config use-context home-prod
