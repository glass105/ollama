# Security

- Do not expose Ollama publicly without authentication or another protective layer.
- Prefer SSH tunnel, VPN, Tailscale, or Cloudflare Tunnel for remote access.
- Never commit secrets, API keys, tokens, SSH keys, credentials, or private environment files.
- Never commit model files, weights, caches, logs, databases, or generated runtime state.
- Review memory changes before pushing to GitHub.
- Treat OpenClaw agents as high-privilege automation.
- Keep public-facing ports as narrow as possible.
- Rotate any secret immediately if it is accidentally pasted into memory or logs.
