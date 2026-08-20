#!/usr/bin/env python3
"""
app_health_checker.py

Checks whether one or more HTTP(S) applications are UP or DOWN by making
a request and inspecting the HTTP status code + response latency.

Usage:
    python3 app_health_checker.py --url https://example.com
    python3 app_health_checker.py --url https://example.com --url http://localhost:8080 --watch 30
    python3 app_health_checker.py --config urls.txt --log health_checker.log

A URL is considered:
    UP      - status code in 200-399 range, response received within timeout
    DOWN    - connection error, timeout, or status code >= 400

Exit code is non-zero if any checked URL is DOWN (useful for CI / cron).
"""

import argparse
import sys
import time
import logging
from datetime import datetime
from urllib import request, error


def setup_logger(log_file: str | None) -> logging.Logger:
    logger = logging.getLogger("app_health_checker")
    logger.setLevel(logging.INFO)
    fmt = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", "%Y-%m-%d %H:%M:%S")

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(fmt)
    logger.addHandler(console)

    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(fmt)
        logger.addHandler(file_handler)

    return logger


def check_url(url: str, timeout: float = 5.0) -> dict:
    result = {
        "url": url,
        "status": "DOWN",
        "http_code": None,
        "latency_ms": None,
        "error": None,
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }
    start = time.monotonic()
    try:
        req = request.Request(url, headers={"User-Agent": "app-health-checker/1.0"})
        with request.urlopen(req, timeout=timeout) as resp:
            elapsed_ms = (time.monotonic() - start) * 1000
            code = resp.getcode()
            result["http_code"] = code
            result["latency_ms"] = round(elapsed_ms, 1)
            result["status"] = "UP" if 200 <= code < 400 else "DOWN"
    except error.HTTPError as e:
        result["http_code"] = e.code
        result["latency_ms"] = round((time.monotonic() - start) * 1000, 1)
        result["status"] = "UP" if 200 <= e.code < 400 else "DOWN"
        result["error"] = f"HTTPError: {e.code} {e.reason}"
    except error.URLError as e:
        result["error"] = f"URLError: {e.reason}"
    except TimeoutError:
        result["error"] = "Timeout"
    except Exception as e:  # noqa: BLE001 - want to catch and report any failure
        result["error"] = f"{type(e).__name__}: {e}"

    return result


def load_urls_from_file(path: str) -> list[str]:
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]


def run_once(urls: list[str], timeout: float, logger: logging.Logger) -> bool:
    all_up = True
    for url in urls:
        r = check_url(url, timeout=timeout)
        if r["status"] == "UP":
            logger.info(
                "%s is UP (HTTP %s, %sms)", r["url"], r["http_code"], r["latency_ms"]
            )
        else:
            all_up = False
            logger.error(
                "%s is DOWN (HTTP %s, error=%s)",
                r["url"], r["http_code"], r["error"],
            )
    return all_up


def main():
    parser = argparse.ArgumentParser(description="Check HTTP application health/uptime.")
    parser.add_argument("--url", action="append", default=[], help="URL to check (repeatable)")
    parser.add_argument("--config", help="Path to a file with one URL per line")
    parser.add_argument("--timeout", type=float, default=5.0, help="Request timeout in seconds")
    parser.add_argument("--watch", type=int, default=0, help="Repeat every N seconds (0 = run once)")
    parser.add_argument("--log", help="Path to log file (in addition to console output)")
    args = parser.parse_args()

    urls = list(args.url)
    if args.config:
        urls.extend(load_urls_from_file(args.config))

    if not urls:
        parser.error("Provide at least one --url or a --config file of URLs")

    logger = setup_logger(args.log)

    if args.watch > 0:
        logger.info("Watching %d URL(s) every %ds. Ctrl+C to stop.", len(urls), args.watch)
        try:
            while True:
                run_once(urls, args.timeout, logger)
                time.sleep(args.watch)
        except KeyboardInterrupt:
            logger.info("Stopped by user.")
            sys.exit(0)
    else:
        ok = run_once(urls, args.timeout, logger)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
