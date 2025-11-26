import os
import sys
import time
import json
import random
import mimetypes
import http.client
from urllib.parse import urlencode
from html.parser import HTMLParser
from typing import Optional, List, Tuple


API_HOST = "api.telegram.org"
POLL_TIMEOUT_SEC = 50  # long polling duration
SLEEP_BETWEEN_ERRORS_SEC = 5


def getenv_strict(name: str) -> str:
    val = os.getenv(name)
    if not val:
        raise RuntimeError(f"Environment variable {name} is not set. Please set it to your bot token.")
    return val


def find_html_files(root_path: str):
    exts = {".html", ".htm"}
    files = []
    for base, _, names in os.walk(root_path):
        for n in names:
            if os.path.splitext(n)[1].lower() in exts:
                files.append(os.path.join(base, n))
    return files


def http_get_json(host: str, path: str, params: dict):
    conn = http.client.HTTPSConnection(host, timeout=POLL_TIMEOUT_SEC + 10)
    try:
        qp = urlencode(params)
        full_path = f"{path}?{qp}" if qp else path
        conn.request("GET", full_path)
        resp = conn.getresponse()
        data = resp.read()
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}: {data[:200]!r}")
        obj = json.loads(data.decode("utf-8"))
        return obj
    finally:
        conn.close()


def http_post_json(host: str, path: str, body_obj: dict):
    data = json.dumps(body_obj).encode("utf-8")
    conn = http.client.HTTPSConnection(host, timeout=60)
    try:
        conn.request(
            "POST",
            path,
            body=data,
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "Content-Length": str(len(data)),
            },
        )
        resp = conn.getresponse()
        resp_data = resp.read()
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}: {resp_data[:500]!r}")
        return json.loads(resp_data.decode("utf-8"))
    finally:
        conn.close()


def build_multipart(fields: dict, files: dict):
    """Builds a multipart/form-data body.

    fields: {name: value}
    files: {name: (filename, bytes, content_type)}
    Returns: (content_type_header_value, body_bytes)
    """
    boundary = f"----WebKitFormBoundary{random.randrange(10**15, 10**16-1)}"
    lines = []

    def add(s: str):
        lines.append(s.encode("utf-8"))

    for name, value in (fields or {}).items():
        add(f"--{boundary}")
        add(f"Content-Disposition: form-data; name=\"{name}\"")
        add("")
        add(str(value))

    for name, (filename, content, ctype) in (files or {}).items():
        add(f"--{boundary}")
        add(
            f"Content-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\""
        )
        add(f"Content-Type: {ctype}")
        add("")
        # binary content
        lines.append(content)

    add(f"--{boundary}--")
    add("")

    body = b"\r\n".join(lines)
    ctype_header = f"multipart/form-data; boundary={boundary}"
    return ctype_header, body


def http_post_multipart_json(host: str, path: str, fields: dict, files: dict):
    ctype, body = build_multipart(fields, files)
    conn = http.client.HTTPSConnection(host, timeout=60)
    try:
        conn.request(
            "POST",
            path,
            body=body,
            headers={
                "Content-Type": ctype,
                "Content-Length": str(len(body)),
            },
        )
        resp = conn.getresponse()
        data = resp.read()
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status}: {data[:200]!r}")
        return json.loads(data.decode("utf-8"))
    finally:
        conn.close()


def send_document(token: str, chat_id: int, file_path: str, caption: Optional[str] = None):
    filename = os.path.basename(file_path)
    ctype, _ = mimetypes.guess_type(filename)
    if not ctype:
        ctype = "application/octet-stream"
    with open(file_path, "rb") as f:
        content = f.read()

    path = f"/bot{token}/sendDocument"
    fields = {"chat_id": str(chat_id)}
    if caption is not None:
        # Telegram supports captions on document messages
        fields["caption"] = caption
    res = http_post_multipart_json(
        API_HOST,
        path,
        fields=fields,
        files={"document": (filename, content, ctype)},
    )
    if not res.get("ok"):
        raise RuntimeError(f"sendDocument failed: {res}")
    return res


# ----- Telegram helpers -----
def send_message(token: str, chat_id: int, text: str):
    # Telegram messages have a 4096 character limit for text
    if len(text) > 4096:
        text = text[:4093] + "..."
    path = f"/bot{token}/sendMessage"
    res = http_get_json(API_HOST, path, {"chat_id": chat_id, "text": text})
    if not res.get("ok"):
        raise RuntimeError(f"sendMessage failed: {res}")
    return res


# ----- Input inspection helpers -----
def _contains_danger(text: Optional[str]) -> bool:
    """Return True if the text contains an exclamation mark or a common
    Unicode danger/warning sign. The check is simple substring search.

    Covered examples include:
      ! ！ ¡ ❗ ‼ ⚠ ⛔ 🚫 ☢ ☣ ☠ 🆘 🛑 🚨
    """
    if not text:
        return False
    symbols = (
        "!",  # ASCII exclamation
        "！",  # Fullwidth exclamation (CJK)
        "¡",  # Inverted exclamation (Spanish)
        "❗",  # Heavy exclamation mark symbol
        "‼",  # Double exclamation mark
        "⚠",  # Warning sign
        "⛔",  # No entry
        "🚫",  # Prohibited
        "🛑",  # Stop sign
        "🚨",  # Police car light
        "☢",  # Radioactive
        "☣",  # Biohazard
        "☠",  # Skull and crossbones
        "🆘",  # SOS
    )
    t = str(text)
    return any(sym in t for sym in symbols)


def _ends_with_double_q(text: Optional[str]) -> bool:
    """Return True if the text ends with a question mark (any of common scripts).

    Triggers when the input ends with a single question mark in:
      - ASCII '?'
      - Fullwidth '？' (CJK)
      - Arabic '؟'
    Whitespace at the end is ignored.
    Note: For convenience, this also returns True if there are multiple trailing
    question marks; i.e., it checks that the last non-space character is a
    question mark in any supported script.
    """
    if not text:
        return False
    t = str(text).rstrip()
    return t.endswith("?") or t.endswith("？") or t.endswith("؟")


def _build_xpaths_report(html_bytes: Optional[bytes]) -> str:
    """Build a report of XPaths and their extracted values.

    Includes configured keys and legacy ones; also shows built-in defaults.
    Note: kept for backward compatibility, but the user-facing "?" trigger now
    sends only DEFAULT_1..4 values via _build_defaults_values().
    """
    if not html_bytes:
        return ""

    lines: List[str] = []

    def add_line(label: str, xpath_env_key: Optional[str] = None, xpath_literal: Optional[str] = None):
        xpath = None
        if xpath_literal:
            xpath = xpath_literal
        elif xpath_env_key:
            xpath = os.getenv(xpath_env_key) or None

        value = ""
        try:
            if xpath_env_key:
                value = _extract_text_for_env_xpath(html_bytes, xpath_env_key) or ""
        except Exception:
            value = ""

        if xpath:
            lines.append(f"{label}: {xpath} -> {value}")
        else:
            # If xpath not set in env for this label, still show value if any
            if value:
                lines.append(f"{label}: (not set) -> {value}")
            else:
                lines.append(f"{label}: (not set)")

    # Configured/new keys
    add_line("EST_XPATH_MAIN", "EST_XPATH_MAIN")
    add_line("xGeneral", "xGeneral")
    add_line("xMarriga", "xMarriga")
    add_line("xOriginal", "xOriginal")
    add_line("xTrade", "xTrade")
    # Legacy keys
    add_line("EST_XPATH_FIRST", "EST_XPATH_FIRST")
    add_line("EST_XPATH_SECOND", "EST_XPATH_SECOND")
    add_line("EST_XPATH_THIRD", "EST_XPATH_THIRD")

    # Built-in defaults documented in extract_span_text_for_fixed_xpath
    defaults = [
        ("DEFAULT_1", "/html/body/div[1]/div[2]/span"),
        ("DEFAULT_2", "/html/body/div[2]/div[2]/span"),
        ("DEFAULT_3", "/html/body/div[4]/div[2]/span"),
        ("DEFAULT_4", "/html/body/div[7]/p"),
    ]
    # For defaults, we can reuse the parser directly
    try:
        text = html_bytes.decode("utf-8", errors="ignore")
    except Exception:
        text = html_bytes.decode(errors="ignore")
    parser = _SimpleHTMLTree()
    parser.feed(text)
    root = parser.root

    def traverse(simple_xpath: str) -> str:
        spec = _parse_simple_xpath(simple_xpath)
        node = root
        for tag, idx in spec:
            node = _find_nth_child(node, tag, idx)
            if not node:
                return ""
        return _collect_text(node)

    for label, xp in defaults:
        val = traverse(xp) or ""
        lines.append(f"{label}: {xp} -> {val}")

    report = "\n".join(lines).strip()
    # Telegram has 4096 char limit; send_message will trim, but keep report concise
    if len(report) > 4000:
        report = report[:3997] + "..."
    return report


def _build_defaults_values(html_bytes: Optional[bytes]) -> str:
    """Return ONLY the values for DEFAULT_1..4, one per line, with labels.

    Output format:
      DEFAULT_1: <value>
      DEFAULT_2: <value>
      DEFAULT_3: <value>
      DEFAULT_4: <value>
    """
    if not html_bytes:
        return ""
    # Prepare parser
    try:
        text = html_bytes.decode("utf-8", errors="ignore")
    except Exception:
        text = html_bytes.decode(errors="ignore")
    parser = _SimpleHTMLTree()
    parser.feed(text)
    root = parser.root

    defaults = [
        ("DEFAULT_1", "/html/body/div[2]/div[2]/span"),
        ("DEFAULT_2", "/html/body/div[3]/div[2]/span"),
        ("DEFAULT_3", "/html/body/div[4]/div[2]/span"),
        ("DEFAULT_4", "/html/body/div[7]/p"),
    ]

    def traverse(simple_xpath: str) -> str:
        spec = _parse_simple_xpath(simple_xpath)
        node = root
        for tag, idx in spec:
            node = _find_nth_child(node, tag, idx)
            if not node:
                return ""
        return _collect_text(node)

    lines: List[str] = []
    for label, xp in defaults:
        val = traverse(xp) or ""
        lines.append(f"{val}")

    out = "\n".join(lines).strip()
    if len(out) > 4000:
        out = out[:3997] + "..."
    return out


def _extract_defaults_list(html_bytes: Optional[bytes]) -> List[Tuple[str, str]]:
    """Return a list of (label, value) for DEFAULT_1..4 in order.

    If html_bytes is None or parsing fails, values may be empty strings.
    """
    if not html_bytes:
        return []
    try:
        text = html_bytes.decode("utf-8", errors="ignore")
    except Exception:
        text = html_bytes.decode(errors="ignore")
    parser = _SimpleHTMLTree()
    parser.feed(text)
    root = parser.root

    defaults = [
        ("DEFAULT_1", "/html/body/div[1]/div[2]/span"),
        ("DEFAULT_2", "/html/body/div[2]/div[2]/span"),
        ("DEFAULT_3", "/html/body/div[4]/div[2]/span"),
        ("DEFAULT_4", "/html/body/div[7]/p"),
    ]

    def traverse(simple_xpath: str) -> str:
        spec = _parse_simple_xpath(simple_xpath)
        node = root
        for tag, idx in spec:
            node = _find_nth_child(node, tag, idx)
            if not node:
                return ""
        return _collect_text(node)

    out: List[Tuple[str, str]] = []
    for label, xp in defaults:
        val = traverse(xp) or ""
        out.append((label, val))
    return out


def _count_trailing_dots(text: Optional[str]) -> int:
    """Count trailing dot characters at the end of the string.

    Supported dot forms include:
      - '.' ASCII full stop
      - '．' Fullwidth full stop (U+FF0E)
      - '。' Ideographic full stop (U+3002)
      - '۔' Arabic full stop (U+06D4)
    Trailing whitespace is ignored.
    """
    if not text:
        return 0
    t = str(text).rstrip()
    if not t:
        return 0
    dots = {".", "．", "。", "۔"}
    count = 0
    for ch in reversed(t):
        if ch in dots:
            count += 1
        else:
            break
    return count


# ----- Minimal HTML parser for fixed XPath extraction -----
class _Node:
    def __init__(self, tag: Optional[str]):
        self.tag = tag
        self.children: List[_Node] = []
        self.text_parts: List[str] = []

    def add_child(self, child: "_Node"):
        self.children.append(child)

    def add_text(self, text: str):
        if text:
            self.text_parts.append(text)


class _SimpleHTMLTree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = _Node(None)
        self._stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = _Node(tag.lower())
        self._stack[-1].add_child(node)
        self._stack.append(node)

    def handle_endtag(self, tag):
        # Pop until matching tag or root
        t = tag.lower()
        for i in range(len(self._stack) - 1, 0, -1):
            if self._stack[i].tag == t:
                del self._stack[i:]
                break

    def handle_data(self, data):
        if data and self._stack:
            self._stack[-1].add_text(data)


def _find_nth_child(node: _Node, tag: str, index_1based: int) -> Optional[_Node]:
    count = 0
    t = tag.lower()
    for ch in node.children:
        if ch.tag == t:
            count += 1
            if count == index_1based:
                return ch
    return None


def _collect_text(node: _Node) -> str:
    parts = []
    if node.text_parts:
        parts.extend(node.text_parts)
    for ch in node.children:
        parts.append(_collect_text(ch))
    return "".join(parts).strip()


def extract_span_text_for_fixed_xpath(html_bytes: bytes) -> str:
    """Extract text from a set of XPaths in the HTML bytes.

    Order of XPaths (first non-empty match wins):
      - From environment variables if provided (in this order):
        EST_XPATH_MAIN, xGeneral, xMarriga, xOriginal, xTrade
        (Legacy fallback supported: EST_XPATH_FIRST, EST_XPATH_SECOND, EST_XPATH_THIRD)
      - Otherwise, built-in defaults:
      - /html/body/div[1]/div[2]/span
      - /html/body/div[2]/div[2]/span
      - /html/body/div[4]/div[2]/span
      - /html/body/div[7]/p

    If none match or segments are missing, returns empty string.
    """
    try:
        text = html_bytes.decode("utf-8", errors="ignore")
    except Exception:
        text = html_bytes.decode(errors="ignore")

    parser = _SimpleHTMLTree()
    parser.feed(text)
    root = parser.root

    def _traverse_path(path_spec):
        node = root
        for tag, idx in path_spec:
            node = _find_nth_child(node, tag, idx)
            if not node:
                return None
        return node

    # Get configured XPaths or fallback defaults (as (tag, index) sequences)
    xpaths = _configured_xpath_specs()

    for spec in xpaths:
        node = _traverse_path(spec)
        if node:
            txt = _collect_text(node)
            if txt:
                return txt
    return ""


# Helper: extract text for a specific XPath provided via an env var name (e.g., "xGeneral")
def _extract_text_for_env_xpath(html_bytes: bytes, env_var_name: str) -> str:
    """Extract text from HTML using a single XPath specified in environment.

    If the env var is undefined or invalid, returns empty string.
    """
    xpath = os.getenv(env_var_name, "")
    spec = _parse_simple_xpath(xpath) if xpath else None
    if not spec:
        return ""
    try:
        text = html_bytes.decode("utf-8", errors="ignore")
    except Exception:
        text = html_bytes.decode(errors="ignore")

    parser = _SimpleHTMLTree()
    parser.feed(text)
    root = parser.root

    node = root
    for tag, idx in spec:
        node = _find_nth_child(node, tag, idx)
        if not node:
            return ""
    return _collect_text(node)


# ----- Simple XPath configuration (via env) -----
def _parse_simple_xpath(xpath: str) -> Optional[List[Tuple[str, int]]]:
    """Parse a very small subset of XPath used by this project.

    Supported form: /html/body/div[2]/div[2]/span (leading slash optional)
    - Only tag names and optional 1-based indices in square brackets are supported.
    - If index is omitted, defaults to 1.
    Returns a list of (tag_lowercase, index) or None if invalid.
    """
    if not xpath:
        return None
    s = xpath.strip()
    if not s:
        return None
    if s.startswith("/"):
        s = s[1:]
    if not s:
        return None
    parts = [p for p in s.split("/") if p]
    if not parts:
        return None
    spec: List[Tuple[str, int]] = []
    for p in parts:
        p = p.strip()
        if not p:
            return None
        tag = p
        idx = 1
        if "[" in p and p.endswith("]"):
            try:
                tag, idx_str = p.split("[", 1)
                idx = int(idx_str[:-1])
                if idx < 1:
                    return None
            except Exception:
                return None
        tag = tag.strip().lower()
        if not tag.isidentifier():
            # basic validation; tags like 'div', 'span', 'p', 'body', 'html'
            return None
        spec.append((tag, idx))
    return spec


def _configured_xpath_specs() -> List[List[Tuple[str, int]]]:
    """Build the ordered list of XPath specs from environment variables.

    Environment variables (first to last):
      - EST_XPATH_MAIN
      - xGeneral
      - xMarriga
      - xOriginal
      - xTrade
      - (legacy fallbacks)
        • EST_XPATH_FIRST
        • EST_XPATH_SECOND
        • EST_XPATH_THIRD

    Invalid entries are ignored. If none present, fall back to built-in defaults.
    Duplicate specs are removed while preserving order.
    """
    env_vars = [
        "EST_XPATH_MAIN",
        # new names
        "xGeneral",
        "xMarriga",
        "xOriginal",
        "xTrade",
        # legacy names for backward compatibility
        "EST_XPATH_FIRST",
        "EST_XPATH_SECOND",
        "EST_XPATH_THIRD",
    ]
    specs: List[List[Tuple[str, int]]] = []
    seen = set()
    for name in env_vars:
        val = os.getenv(name)
        if not val:
            continue
        spec = _parse_simple_xpath(val)
        if not spec:
            continue
        key = tuple(spec)
        if key in seen:
            continue
        seen.add(key)
        specs.append(spec)

    if specs:
        return specs
    # default fixed XPaths
    return [
        [("html", 1), ("body", 1), ("div", 1), ("div", 2), ("span", 1)],
        [("html", 1), ("body", 1), ("div", 2), ("div", 2), ("span", 1)],
        [("html", 1), ("body", 1), ("div", 4), ("div", 2), ("span", 1)],
        [("html", 1), ("body", 1), ("div", 7), ("p", 1)],
    ]


def get_updates(token: str, offset):
    path = f"/bot{token}/getUpdates"
    params = {"timeout": POLL_TIMEOUT_SEC}
    if offset is not None:
        params["offset"] = offset
    res = http_get_json(API_HOST, path, params)
    if not res.get("ok"):
        raise RuntimeError(f"getUpdates failed: {res}")
    return res["result"]


def gemini_generate(
    api_key: str,
    model: str,
    user_text: str,
    xpath_value: str,
    prompt_template: Optional[str] = None,
    extra_vars: Optional[dict] = None,
) -> str:
    """Generate text using Google's official genai SDK.

    This follows the template recommended by Google:
        from google import genai
        client = genai.Client()
        response = client.models.generate_content(
            model="gemini-2.5-flash", contents="..."
        )
        print(response.text)

    We pass the API key explicitly to avoid relying on the ambient environment,
    but the SDK also supports pulling it from GEMINI_API_KEY automatically.
    """
    try:
        from google import genai  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "google-genai package is not installed. Install it with: pip install google-genai"
        ) from e

    # Compose the contents string using a configurable template
    # Supported placeholders:
    #   {user_text}, {xpath_value}, {chat_username}, {chat_first_name}, {chat_last_name}, {chat_title}
    # Unknown/missing placeholders resolve to empty string.
    default_template = (
        "User message: {user_text}\n"
        "Extracted HTML value: {xpath_value}"
    )

    class _SafeDict(dict):
        def __missing__(self, key):  # type: ignore[override]
            return ""

    vars_all = {
        "user_text": user_text or "",
        "xpath_value": xpath_value or "",
    }
    if extra_vars:
        vars_all.update({k: (v if v is not None else "") for k, v in extra_vars.items()})

    tpl = prompt_template or os.getenv("PROMPT_TEMPLATE") or os.getenv("EST_PROMPT_TEMPLATE") or default_template
    try:
        contents = tpl.format_map(_SafeDict(vars_all))
    except Exception:
        # Fallback to default if the provided template has format errors
        contents = default_template.format_map(_SafeDict(vars_all))

    # Instantiate client. If api_key is empty, the SDK will try GEMINI_API_KEY from env.
    client = genai.Client(api_key=api_key) if api_key else genai.Client()

    # Call the model using the official method API
    try:
        response = client.models.generate_content(model=model, contents=contents)
    except Exception as e:
        # Provide a graceful fallback if the configured model is invalid or unsupported
        emsg = str(e)
        not_found_hints = (
            "NOT_FOUND",
            "is not found",
            "supported for generateContent",
        )
        if any(h in emsg for h in not_found_hints):
            # Retry once with Google's current safe default model from the template.
            fallback_model = "gemini-2.5-flash"
            if model != fallback_model:
                try:
                    response = client.models.generate_content(
                        model=fallback_model, contents=contents
                    )
                except Exception:
                    # Re-raise original error if fallback also fails
                    raise
            else:
                # Already the fallback model, re-raise
                raise
        else:
            # Unknown error, re-raise
            raise
    text = getattr(response, "text", None)
    if text:
        return str(text).strip()
    # Fallback to stringifying response if .text is absent
    try:
        return json.dumps(response, ensure_ascii=False)[:4000]
    except Exception:
        return ""


def main():
    token = getenv_strict("TELEGRAM_BOT_TOKEN")
    gemini_api_key = getenv_strict("GEMINI_API_KEY")
    # Use Google's template default model unless overridden
    gemini_model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
    # Default directory as per issue description
    default_dir = r"D:\SDK\estHTML"
    html_dir = os.getenv("EST_HTML_DIR", default_dir)

    if not os.path.isdir(html_dir):
        print(f"ERROR: HTML directory not found: {html_dir}", file=sys.stderr)
        sys.exit(2)

    html_files = find_html_files(html_dir)
    if not html_files:
        print(f"ERROR: No .html/.htm files found under: {html_dir}", file=sys.stderr)
        sys.exit(3)

    print("Telegram bot started. Waiting for messages...")
    print(f"Serving random HTML pages from: {html_dir}")

    offset = None
    try:
        while True:
            try:
                updates = get_updates(token, offset)
                for upd in updates:
                    offset = max(offset or 0, upd.get("update_id", 0) + 1)
                    msg = upd.get("message") or upd.get("edited_message") or {}
                    chat = msg.get("chat") or {}
                    chat_id = chat.get("id")
                    if not chat_id:
                        continue

                    # On any input, pick a random HTML file and extract the fixed XPath value
                    choice = random.choice(html_files)
                    xpath_value = ""
                    try:
                        with open(choice, "rb") as fh:
                            html_bytes = fh.read()
                        xpath_value = extract_span_text_for_fixed_xpath(html_bytes) or ""
                    except Exception:
                        xpath_value = ""

                    # Compose prompt for Gemini using user's message text and the XPath value
                    user_text = msg.get("text") or ""
                    # Flag: when input ends with a question mark (any supported script),
                    # send ONLY the values of DEFAULT_1..4 as a follow-up message.
                    want_xpaths_report = _ends_with_double_q(user_text)
                    # Count trailing dots to trigger per-default separate messages
                    dots_count = _count_trailing_dots(user_text)
                    # Prepare extra variables for the template context
                    extra_vars = {
                        "chat_username": chat.get("username") or "",
                        "chat_first_name": chat.get("first_name") or "",
                        "chat_last_name": chat.get("last_name") or "",
                        "chat_title": chat.get("title") or "",
                    }
                    # Route logic: only call Gemini if the input contains a danger sign; else return xGeneral/xpath.
                    if not _contains_danger(user_text):
                        try:
                            xgeneral_value = _extract_text_for_env_xpath(html_bytes, "xGeneral") if 'html_bytes' in locals() else ""
                        except Exception:
                            xgeneral_value = ""
                        reply_text = xgeneral_value or (xpath_value or "")
                        try:
                            send_message(token, chat_id, reply_text)
                        except Exception:
                            pass
                        # If user asked for DEFAULTS values, send them as a follow-up message
                        if want_xpaths_report:
                            try:
                                defaults_vals = _build_defaults_values(html_bytes if 'html_bytes' in locals() else None)
                                if defaults_vals:
                                    send_message(token, chat_id, defaults_vals)
                            except Exception:
                                pass
                        # If user ended with dots, send per-default values as separate messages
                        if dots_count > 0:
                            try:
                                pairs = _extract_defaults_list(html_bytes if 'html_bytes' in locals() else None)
                                if pairs:
                                    if dots_count <= 4:
                                        to_send = pairs[:dots_count]
                                    else:
                                        to_send = pairs[:4]
                                    for label, val in to_send:
                                        text_out = f"{label}: {val}".strip()
                                        if text_out:
                                            send_message(token, chat_id, text_out)
                            except Exception:
                                pass
                        continue
                    try:
                        ai_text = gemini_generate(
                            gemini_api_key,
                            gemini_model,
                            user_text,
                            xpath_value,
                            prompt_template=None,  # can be overridden by env vars inside function
                            extra_vars=extra_vars,
                        )
                        # Always send Gemini response as-is; newline-based actions removed per requirement.
                        send_message(token, chat_id, ai_text)
                        if want_xpaths_report:  # send DEFAULTS values after AI reply
                            try:
                                defaults_vals = _build_defaults_values(html_bytes if 'html_bytes' in locals() else None)
                                if defaults_vals:
                                    send_message(token, chat_id, defaults_vals)
                            except Exception:
                                pass
                        # Dot-trigger per-default messages after AI reply
                        if dots_count > 0:
                            try:
                                pairs = _extract_defaults_list(html_bytes if 'html_bytes' in locals() else None)
                                if pairs:
                                    if dots_count <= 4:
                                        to_send = pairs[:dots_count]
                                    else:
                                        to_send = pairs[:4]
                                    for label, val in to_send:
                                        text_out = f"{label}: {val}".strip()
                                        if text_out:
                                            send_message(token, chat_id, text_out)
                            except Exception:
                                pass
                    except Exception as e:
                        # Do NOT send the error to the user. Instead, reply with xGeneral value.
                        # Log the error locally for diagnostics.
                        print(f"Gemini error: {e}", file=sys.stderr)
                        try:
                            xgeneral_value = _extract_text_for_env_xpath(html_bytes, "xGeneral") if 'html_bytes' in locals() else ""
                        except Exception:
                            xgeneral_value = ""
                        # Fallback to previously extracted xpath_value if xGeneral missing/empty
                        reply_text = xgeneral_value or (xpath_value or "")
                        if reply_text:
                            try:
                                send_message(token, chat_id, reply_text)
                            except Exception:
                                pass
                        # Optionally send DEFAULTS values even on error fallback
                        if want_xpaths_report:
                            try:
                                defaults_vals = _build_defaults_values(html_bytes if 'html_bytes' in locals() else None)
                                if defaults_vals:
                                    send_message(token, chat_id, defaults_vals)
                            except Exception:
                                pass
                        # Dot-trigger per-default messages even on error
                        if dots_count > 0:
                            try:
                                pairs = _extract_defaults_list(html_bytes if 'html_bytes' in locals() else None)
                                if pairs:
                                    if dots_count <= 4:
                                        to_send = pairs[:dots_count]
                                    else:
                                        to_send = pairs[:4]
                                    for label, val in to_send:
                                        text_out = f"{label}: {val}".strip()
                                        if text_out:
                                            send_message(token, chat_id, text_out)
                            except Exception:
                                pass
                # Loop continues, long polling already waited
            except KeyboardInterrupt:
                print("Interrupted by user. Exiting...")
                break
            except Exception as e:
                print(f"Error: {e}")
                time.sleep(SLEEP_BETWEEN_ERRORS_SEC)
    finally:
        pass


if __name__ == "__main__":
    main()
