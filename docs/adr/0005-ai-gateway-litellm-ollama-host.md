# 5. AI gateway: LiteLLM in-cluster, Ollama on the macOS host

Date: 2026-05-02

## Status

Accepted

## Context

The homelab will host AI workloads — first an experimental article-writing system (likely STORM-derived or a GraphRAG/LightRAG composition), with more to follow. Two architectural questions:

1. **Where does the LLM gateway live?** Options:
   - A direct provider SDK in each project (no gateway). Simple but couples each project to a model and provider.
   - **LiteLLM** as an in-cluster gateway: OpenAI-compatible API in front of arbitrary backends (OpenAI, Anthropic, local Ollama, vLLM, etc.). Single integration point, swappable backends, built-in cost tracking, fallbacks, rate limits.
   - A bigger orchestrator (LangServe, LangGraph platform). Heavier, opinionated, premature for this stage.
2. **Where does Ollama run?** Options:
   - **In the cluster** as a `Deployment`. Uniform Kubernetes management; but the M4's Apple Silicon GPU is exposed to containers only via Apple's Virtualization Framework with limitations and historically poor `metal` performance inside Docker containers. Models effectively fall back to CPU inference, which is dramatically slower (5–10× on a 7B-class model).
   - **On the macOS host** (`brew install ollama` or the desktop app). Full Metal acceleration, zero virtualization overhead. Reachable from the cluster via `host.docker.internal:11434`.

Memory math: a single 7B-class model under Ollama uses ~5–8 GiB of resident memory while loaded. Running it inside the container runtime would compete directly with cluster components for the same 16 GB pool, with worse GPU access on top. Running it on the host shares the same RAM pool but at least gets full Metal acceleration.

## Decision

- **LiteLLM** is the AI gateway. Deployed in-cluster via ArgoCD under `platform/ai-gateway/`. All projects under `projects/*` integrate via the LiteLLM endpoint (OpenAI-compatible client), never directly with a provider.
- **Ollama runs on the macOS host**, not in the cluster. LiteLLM is configured to proxy local-model traffic to `http://host.docker.internal:11434` (kind exposes the host gateway to pods automatically).
- Hosted-model API keys (Anthropic, OpenAI) are stored in a Kubernetes Secret managed by external-secrets (decided in a future ADR — for now, manually created Secret marked as such).
- LiteLLM's own DB (for cost tracking and rate limits) is a small Postgres database in the in-cluster CNPG cluster.

## Consequences

- Projects depend on a stable internal endpoint (`http://litellm.ai-gateway.svc.cluster.local:4000`) and a model alias (`local-llama`, `claude-sonnet-4-6`, etc.), not on provider SDKs. Swapping a backend doesn't touch project code.
- Ollama's lifecycle is **not** managed by Kubernetes. It's a host daemon — start/stop via `brew services` or the Ollama app. This is an explicit deviation from "everything in the cluster" and is documented for future me / future readers.
- `host.docker.internal` resolution from kind pods works because we add it to the kind config's `extraHostsEntries`. The bootstrap script verifies this is reachable before declaring success.
- Cost tracking and rate limits become available across all projects centrally, instead of each project rolling its own.
- If we later get a discrete Linux machine with a real GPU, Ollama moves into the cluster (or is replaced by vLLM) and only LiteLLM's backend config changes. Project code is unaffected.
- Trade-off: the platform is no longer fully reproducible from `bootstrap.sh` alone — Ollama install on the host is a documented prerequisite, not automated. Acceptable for a personal lab.
