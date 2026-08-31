#!/usr/bin/env python3
# confirm.py — подтверждение деструктивных команд через репозиторий команд.
#
# Работает вместе с командами, у которых в commands.yaml стоит confirm: true
# и confirm_says: [...]. Собранная команда вызывает --ask, а команда-подтверждение
# (из confirm_says) вызывает --exec. Оба вызова без вывода в приложении.

import json
import os
import subprocess
import sys
import tempfile


def pending_file():
    return os.path.join(tempfile.gettempdir(), "jarvis_confirm.json")


def clean_ask():
    if os.path.exists(pending_file()):
        try:
            os.remove(pending_file())
        except OSError:
            pass


def exec_confirmed():
    if not os.path.exists(pending_file()):
        return
    try:
        with open(pending_file(), "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        clean_ask()
        return
    target = data.get("target")
    clean_ask()
    if not target:
        return
    if os.path.exists(target):
        subprocess.Popen(target, shell=True)


def write_pending(target_rel):
    clean_ask()
    with open(pending_file(), "w", encoding="utf-8") as f:
        json.dump({"target": target_rel}, f)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--ask":
        if len(sys.argv) > 2:
            write_pending(sys.argv[2])
    elif mode == "--exec":
        exec_confirmed()
    elif mode == "--cancel":
        clean_ask()


if __name__ == "__main__":
    main()