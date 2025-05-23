# functions/log_batch_job_status/main.py
import base64, json, uuid, logging
import functions_framework

# ── helper ────────────────────────────────────────────────────────────
def make_logger(invocation_tag: str) -> logging.Logger:
    """
    Returns a logger whose every line starts with the invocation_tag.
    Cloud Logging recognises the standard 'logging' records, so we use it
    instead of raw print().
    """
    logger = logging.getLogger(invocation_tag)
    if logger.handlers:                       # already initialised (cold-start reuse)
        return logger

    handler  = logging.StreamHandler()
    fmt      = f"[{invocation_tag}] %(message)s"
    handler.setFormatter(logging.Formatter(fmt))

    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    logger.propagate = False                  # don't double-print through root logger
    return logger


@functions_framework.cloud_event
def log_batch_job_status_event(event):
    # 1️⃣  create a stable tag for this invocation --------------
    invocation_tag = event.get("id") or uuid.uuid4().hex[:8]
    log = make_logger(invocation_tag)

    log.info("Batch Job Status Logger function was triggered (start)")

    message = event.data.get("message", {})
    data_b64 = message.get("data", "")
    attributes = message.get("attributes", {})

    # 2️⃣  decode the payload (may be plain text or JSON) -------
    try:
        decoded = base64.b64decode(data_b64).decode("utf-8")
        payload = json.loads(decoded)         # will raise if not JSON
        log.info("Parsed JSON notification:\n%s",
                 json.dumps(payload, indent=2))
    except (ValueError, json.JSONDecodeError):
        log.info("Notification text: %s", decoded)

    if attributes:
        log.info("Message attributes:\n%s",
                 json.dumps(attributes, indent=2))

    log.info("Batch Job Status Logger function completed (end)")
    return "ok", 200
