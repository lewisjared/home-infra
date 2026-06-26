# Ollama

Shared in-cluster Ollama service for lightweight local models.

Current model preload:

- `nomic-embed-text` for OpenViking embeddings

The deployment runs CPU-only for now. Text embedding models are small enough for
this cluster without GPU acceleration; the pod is scheduled onto nodes labelled
`gpu=amd-igpu` so a later ROCm/iGPU experiment can be isolated to those nodes
without changing OpenViking's endpoint.

In-cluster API:

```text
http://ollama.ollama.svc.cluster.local:11434
```
