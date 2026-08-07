#!/usr/bin/env python3
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LISTEN_HOST = os.environ.get("OPEN_WEBUI_MEMORY_PROXY_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("OPEN_WEBUI_MEMORY_PROXY_PORT", "11435"))
OLLAMA_UPSTREAM = os.environ.get("OLLAMA_UPSTREAM_URL", "http://127.0.0.1:11434").rstrip("/")
COMBINED_CONTEXT = os.environ.get("COMBINED_CONTEXT", "/workspace/current_context.md")
DEFAULT_NUM_CTX = int(os.environ.get("OPEN_WEBUI_MEMORY_PROXY_NUM_CTX", "8192"))
DEFAULT_NUM_PREDICT = int(os.environ.get("OPEN_WEBUI_MEMORY_PROXY_NUM_PREDICT", "768"))
STRIP_TOOLS = os.environ.get("OPEN_WEBUI_MEMORY_PROXY_STRIP_TOOLS", "true").strip().lower() in {
    "1",
    "true",
    "yes",
    "y",
    "on",
}


def load_memory_prompt() -> str:
    try:
        with open(COMBINED_CONTEXT, "r", encoding="utf-8") as f:
            context = f.read().strip()
    except FileNotFoundError:
        context = ""

    return f"""You are Qwen running in this disposable RunPod project environment.

The Markdown project memory is already provided below. You are not expected to read files during this chat.
When the user asks what you remember from the MD files or project memory, summarize the provided memory below.
Treat "memory", "MD files", "Markdown memory", and "project memory" as references to this injected GitHub memory context.
Do not use or refer to Open WebUI memory tools such as list_memory_paths for project memory questions; those are separate and may be empty.
Never claim you do not have access to project memory when answering questions about this setup.
Follow MEMORY/OpenWebUI/DECISIONS.md and never store secrets, keys, tokens, logs, caches, databases, or model files in GitHub.

{context}
"""


def inject_memory(payload: dict) -> dict:
    memory_prompt = load_memory_prompt()
    if not memory_prompt.strip():
        return payload

    if STRIP_TOOLS:
        payload.pop("tools", None)
        payload.pop("tool_choice", None)

    options = payload.get("options")
    if not isinstance(options, dict):
        options = {}
    options["num_ctx"] = DEFAULT_NUM_CTX
    if "num_predict" not in options and DEFAULT_NUM_PREDICT > 0:
        options["num_predict"] = DEFAULT_NUM_PREDICT
    payload["options"] = options

    messages = payload.get("messages")
    if isinstance(messages, list):
        if messages and messages[-1].get("role") == "user":
            latest = dict(messages[-1])
            latest["content"] = (
                "Project memory provided for this request:\n"
                f"{memory_prompt}\n\n"
                "User request:\n"
                f"{latest.get('content', '')}"
            )
            payload["messages"] = [*messages[:-1], latest]
        else:
            payload["messages"] = [
                *messages,
                {"role": "user", "content": f"Project memory provided for this request:\n{memory_prompt}"},
            ]
        return payload

    prompt = payload.get("prompt")
    if isinstance(prompt, str):
        payload["prompt"] = f"{prompt}\n\nProject memory provided for this request:\n{memory_prompt}"

    return payload


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward(inject=self.path in ("/api/chat", "/api/generate", "/v1/chat/completions"))

    def do_OPTIONS(self):
        self.forward()

    def forward(self, inject: bool = False):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
        headers = {k: v for k, v in self.headers.items() if k.lower() not in {"host", "content-length"}}

        if inject and body:
            try:
                payload = json.loads(body.decode("utf-8"))
                body = json.dumps(inject_memory(payload)).encode("utf-8")
                headers["Content-Type"] = "application/json"
            except json.JSONDecodeError:
                pass

        url = f"{OLLAMA_UPSTREAM}{self.path}"
        req = Request(url, data=body if self.command != "GET" else None, headers=headers, method=self.command)

        try:
            with urlopen(req, timeout=600) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for key, value in resp.headers.items():
                    if key.lower() not in {"connection", "transfer-encoding", "content-length"}:
                        self.send_header(key, value)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        except HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except URLError as e:
            data = json.dumps({"error": str(e)}).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    def log_message(self, fmt, *args):
        sys.stderr.write("[memory-proxy] " + fmt % args + "\n")


if __name__ == "__main__":
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), ProxyHandler)
    print(f"Open WebUI memory proxy listening on http://{LISTEN_HOST}:{LISTEN_PORT}", flush=True)
    print(f"Forwarding to {OLLAMA_UPSTREAM}", flush=True)
    server.serve_forever()
